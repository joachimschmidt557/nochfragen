package main

import (
	"context"
	"encoding/json"
	"flag"
	"io"
	"io/ioutil"
	"log"
	"net/http"
	"os"

	"github.com/go-redis/redis/v8"
	"github.com/gorilla/sessions"
	"github.com/throttled/throttled/v2"
	"github.com/throttled/throttled/v2/store/memstore"
)

const (
	Hidden = iota
	Visible
	Deleted
	defaultVisibility = Hidden
	maxQuestionLen = 500
)

type Question struct {
	Id         int    `json:"id"`
	Text       string `json:"text"`
	Upvotes    int    `json:"upvotes"`
	Visibility int    `json:"visibility"`
	Upvoted    bool   `json:"upvoted"`
}

type ModifyQuestionRequest struct {
	Id int `json:"id"`
}

type AddQuestionRequest struct {
	Text string `json:"text"`
}

type LoginRequest struct {
	Password string `json:"password"`
}

type LoginStatusResponse struct {
	LoggedIn bool `json:"loggedIn"`
}

var ctx = context.Background()
var rdb *redis.Client
var listenAddress string
var redisAddress string
var store = sessions.NewCookieStore([]byte(os.Getenv("SESSION_KEY")))
var password string

func main() {
	flag.StringVar(&listenAddress, "listen-address", "0.0.0.0:8000", "Address to listen for connections")
	flag.StringVar(&redisAddress, "redis-address", "localhost:6379", "Address to connect to redis")
	flag.Parse()

	rdb = redis.NewClient(&redis.Options{
		Addr:     redisAddress,
		Password: "",
		DB:       0,
	})

	store, err := memstore.New(65536)
	if err != nil {
		log.Fatal(err)
	}

	quota := throttled.RateQuota{
		MaxRate:  throttled.PerMin(30),
		MaxBurst: 5,
	}
	rateLimiter, err := throttled.NewGCRARateLimiter(store, quota)
	if err != nil {
		log.Fatal(err)
	}

	httpRateLimiter := throttled.HTTPRateLimiter{
		RateLimiter: rateLimiter,
		VaryBy: &throttled.VaryBy{
			Path:    true,
			Cookies: []string{"session"},
		},
	}

	mux := http.NewServeMux()

	mux.HandleFunc("/", index)
	mux.Handle("/build/", http.StripPrefix("/build/", http.FileServer(http.Dir("public/build"))))
	mux.HandleFunc("/api/login", login)
	mux.HandleFunc("/api/logout", logout)
	mux.HandleFunc("/api/questions", questions)
	mux.HandleFunc("/api/upvote", upvote)
	mux.HandleFunc("/api/show", show)
	mux.HandleFunc("/api/hide", hide)
	mux.HandleFunc("/api/delete", delete)

	log.Printf("Listening on %v", listenAddress)
	log.Fatal(http.ListenAndServe(listenAddress, httpRateLimiter.RateLimit(mux)))
}

func index(writer http.ResponseWriter, request *http.Request) {
	session, _ := store.Get(request, "session")

	err := session.Save(request, writer)
	if err != nil {
		http.Error(writer, err.Error(), http.StatusInternalServerError)
		return
	}

	http.ServeFile(writer, request, "public/index.html")
}

func login(writer http.ResponseWriter, request *http.Request) {
	session, _ := store.Get(request, "session")

	switch request.Method {
	case "GET":
		auth, ok := session.Values["authenticated"].(bool)
		loggedIn := ok && auth

		response := LoginStatusResponse{
			LoggedIn: loggedIn,
		}

		jsonResult, err := json.Marshal(response)
		if err != nil {
			http.Error(writer, err.Error(), http.StatusInternalServerError)
			return
		}

		_, err = io.WriteString(writer, string(jsonResult))
		if err != nil {
			http.Error(writer, err.Error(), http.StatusInternalServerError)
			return
		}
	case "POST":
		requestBody, err := ioutil.ReadAll(request.Body)
		if err != nil {
			log.Printf("Error reading HTTP request, ignoring request: %v", err)
			return
		}

		var requestData LoginRequest
		err = json.Unmarshal([]byte(requestBody), &requestData)
		if err != nil {
			log.Printf("Error reading HTTP request, ignoring request: %v", err)
			return
		}

		password, err := rdb.Get(ctx, "gutefrage.password").Result()
		if err != nil {
			http.Error(writer, err.Error(), http.StatusInternalServerError)
			return
		}

		if requestData.Password != password {
			http.Error(writer, "Access denied", http.StatusForbidden)
			return
		}

		session.Values["authenticated"] = true
		err = session.Save(request, writer)
		if err != nil {
			http.Error(writer, err.Error(), http.StatusInternalServerError)
			return
		}
	}
}

func logout(writer http.ResponseWriter, request *http.Request) {
	session, _ := store.Get(request, "session")

	switch request.Method {
	case "POST":
		session.Values["authenticated"] = false

		err := session.Save(request, writer)
		if err != nil {
			http.Error(writer, err.Error(), http.StatusInternalServerError)
			return
		}
	}
}

func questions(writer http.ResponseWriter, request *http.Request) {
	session, _ := store.Get(request, "session")

	switch request.Method {
	case "GET":
		auth, ok := session.Values["authenticated"].(bool)
		loggedIn := ok && auth

		lenQuestions, err := rdb.LLen(ctx, "gutefrage.questions").Result()
		if err != nil {
			http.Error(writer, err.Error(), http.StatusInternalServerError)
			return
		}

		filteredQuestions := []Question{}
		for i := int64(0); i < lenQuestions; i++ {
			visibility, err := rdb.LIndex(ctx, "gutefrage.visibility", i).Int()
			text, err := rdb.LIndex(ctx, "gutefrage.questions", i).Result()
			upvotes, err := rdb.LIndex(ctx, "gutefrage.upvotes", i).Int()
			if err != nil {
				http.Error(writer, err.Error(), http.StatusInternalServerError)
				return
			}

			if visibility != Deleted && (loggedIn || visibility == Visible) {
				voted, ok := session.Values[i].(bool)

				question := Question{
					Id:         int(i),
					Text:       text,
					Upvotes:    upvotes,
					Visibility: visibility,
					Upvoted:    ok && voted,
				}
				filteredQuestions = append(filteredQuestions, question)
			}
		}

		jsonResult, err := json.Marshal(filteredQuestions)
		if err != nil {
			http.Error(writer, err.Error(), http.StatusInternalServerError)
			return
		}

		_, err = io.WriteString(writer, string(jsonResult))
		if err != nil {
			http.Error(writer, err.Error(), http.StatusInternalServerError)
			return
		}
	case "POST":
		requestBody, err := ioutil.ReadAll(request.Body)
		if err != nil {
			log.Printf("Error reading HTTP request, ignoring request: %v", err)
			return
		}

		var requestData AddQuestionRequest
		err = json.Unmarshal([]byte(requestBody), &requestData)
		if err != nil {
			log.Printf("Error reading HTTP request, ignoring request: %v", err)
			return
		}

		if requestData.Text == "" {
			http.Error(writer, "Empty question", http.StatusBadRequest)
			return
		}

		if len(requestData.Text) > maxQuestionLen {
			http.Error(writer, "Question too large", http.StatusRequestEntityTooLarge)
			return
		}

		// TODO race condition
		err = rdb.RPush(ctx, "gutefrage.visibility", defaultVisibility).Err()
		err = rdb.RPush(ctx, "gutefrage.questions", requestData.Text).Err()
		err = rdb.RPush(ctx, "gutefrage.upvotes", 0).Err()
		if err != nil {
			http.Error(writer, err.Error(), http.StatusInternalServerError)
			return
		}
	default:
		http.Error(writer, http.StatusText(http.StatusNotImplemented), http.StatusNotImplemented)
	}

}

func upvote(writer http.ResponseWriter, request *http.Request) {
	session, _ := store.Get(request, "session")

	requestBody, err := ioutil.ReadAll(request.Body)
	if err != nil {
		log.Printf("Error reading HTTP request, ignoring request: %v", err)
		return
	}

	var requestData ModifyQuestionRequest
	err = json.Unmarshal([]byte(requestBody), &requestData)
	if err != nil {
		log.Printf("Error reading HTTP request, ignoring request: %v", err)
		return
	}

	id := int64(requestData.Id)
	if voted, ok := session.Values[id].(bool); !ok || !voted {
		lenQuestions, err := rdb.LLen(ctx, "gutefrage.questions").Result()
		if err != nil {
			http.Error(writer, err.Error(), http.StatusInternalServerError)
			return
		}

		if id >= lenQuestions {
			http.Error(writer, err.Error(), http.StatusBadRequest)
			return
		}

		upvotes, err := rdb.LIndex(ctx, "gutefrage.upvotes", id).Int()
		err = rdb.LSet(ctx, "gutefrage.upvotes", id, upvotes+1).Err()
		if err != nil {
			http.Error(writer, err.Error(), http.StatusInternalServerError)
			return
		}

		session.Values[id] = true
		err = session.Save(request, writer)
		if err != nil {
			http.Error(writer, err.Error(), http.StatusInternalServerError)
			return
		}
	} else {
		http.Error(writer, http.StatusText(http.StatusBadRequest), http.StatusBadRequest)
		return
	}
}

func show(writer http.ResponseWriter, request *http.Request) {
	changeVisibility(writer, request, Visible)
}

func hide(writer http.ResponseWriter, request *http.Request) {
	changeVisibility(writer, request, Hidden)
}

func delete(writer http.ResponseWriter, request *http.Request) {
	changeVisibility(writer, request, Deleted)
}

func changeVisibility(writer http.ResponseWriter, request *http.Request, visibility int) {
	session, _ := store.Get(request, "session")

	if auth, ok := session.Values["authenticated"].(bool); !ok || !auth {
		http.Error(writer, "Forbidden", http.StatusForbidden)
		return
	}

	requestBody, err := ioutil.ReadAll(request.Body)
	if err != nil {
		log.Printf("Error reading HTTP request, ignoring request: %v", err)
		return
	}

	var requestData ModifyQuestionRequest
	err = json.Unmarshal([]byte(requestBody), &requestData)
	if err != nil {
		log.Printf("Error reading HTTP request, ignoring request: %v", err)
		return
	}

	id := int64(requestData.Id)

	lenQuestions, err := rdb.LLen(ctx, "gutefrage.questions").Result()
	if err != nil {
		http.Error(writer, err.Error(), http.StatusInternalServerError)
		return
	}

	if id >= lenQuestions {
		http.Error(writer, err.Error(), http.StatusBadRequest)
		return
	}

	err = rdb.LSet(ctx, "gutefrage.visibility", id, visibility).Err()
	if err != nil {
		http.Error(writer, err.Error(), http.StatusInternalServerError)
		return
	}
}
