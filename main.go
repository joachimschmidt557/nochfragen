package main

import (
	"context"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"strconv"

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
	maxQuestionLen    = 500
	keyPrefix         = "gutefrage:"
)

type StoredQuestion struct {
	Text       string `redis:"text"`
	Upvotes    int    `redis:"upvotes"`
	Visibility int    `redis:"visibility"`
}

type QuestionRange struct {
	Start int
	End   int
}

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
var store *sessions.CookieStore

func main() {
	listenAddress := flag.String("listen-address", "0.0.0.0:8000", "Address to listen for connections")
	redisAddress := flag.String("redis-address", "localhost:6379", "Address to connect to redis")
	generateSessionKey := flag.Bool("generate-session-key", false, "Generate and print a session key and exit instead of running server")
	flag.Parse()

	if *generateSessionKey {
		sessionKey := make([]byte, 32)
		_, err := rand.Read(sessionKey)
		if err != nil {
			log.Fatal(err)
		}
		encoded := base64.StdEncoding.EncodeToString(sessionKey)

		fmt.Printf("SESSION_KEY=%v\n", encoded)
		return
	}

	rdb = redis.NewClient(&redis.Options{
		Addr:     *redisAddress,
		Password: "",
		DB:       0,
	})

	encodedSessionKey := os.Getenv("SESSION_KEY")
	sessionKey, err := base64.StdEncoding.DecodeString(encodedSessionKey)
	if err != nil {
		log.Fatal(err)
	}
	store = sessions.NewCookieStore(sessionKey)

	throttledStore, err := memstore.New(65536)
	if err != nil {
		log.Fatal(err)
	}

	quota := throttled.RateQuota{
		MaxRate:  throttled.PerMin(30),
		MaxBurst: 5,
	}
	rateLimiter, err := throttled.NewGCRARateLimiter(throttledStore, quota)
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
	mux.HandleFunc("/api/export", export)
	mux.HandleFunc("/api/exportall", exportAll)

	log.Printf("Listening on %v", *listenAddress)
	log.Fatal(http.ListenAndServe(*listenAddress, httpRateLimiter.RateLimit(mux)))
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

		encoder := json.NewEncoder(writer)
		err := encoder.Encode(response)
		if err != nil {
			http.Error(writer, err.Error(), http.StatusInternalServerError)
			return
		}
	case "POST":
		var requestData LoginRequest
		decoder := json.NewDecoder(request.Body)
		err := decoder.Decode(&requestData)

		password, err := rdb.Get(ctx, fmt.Sprintf("%vpassword", keyPrefix)).Result()
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

func (questionRange QuestionRange) validId(id int) bool {
	return questionRange.Start <= id && id < questionRange.End
}

func getQuestionRange() (QuestionRange, error) {
	result, err := rdb.MGet(ctx, fmt.Sprintf("%vquestions-start", keyPrefix), fmt.Sprintf("%vquestions-end", keyPrefix)).Result()
	if err != nil {
		return QuestionRange{}, err
	}

	questionRange := QuestionRange{
		Start: 0,
		End:   0,
	}
	if str, ok := result[0].(string); ok {
		start, err := strconv.ParseInt(str, 10, 0)
		if err != nil {
			return QuestionRange{}, err
		}
		questionRange.Start = int(start)
	}
	if str, ok := result[1].(string); ok {
		end, err := strconv.ParseInt(str, 10, 0)
		if err != nil {
			return QuestionRange{}, err
		}
		questionRange.End = int(end)
	}

	return questionRange, nil
}

func getStoredQuestion(id int) (StoredQuestion, error) {
	key := fmt.Sprintf("%vquestion:%v", keyPrefix, id)
	result := rdb.HMGet(ctx, key, "text", "visibility", "upvotes")
	if err := result.Err(); err != nil {
		return StoredQuestion{}, err
	}

	var storedQuestion StoredQuestion
	err := result.Scan(&storedQuestion)
	if err != nil {
		return StoredQuestion{}, err
	}

	return storedQuestion, nil
}

func questions(writer http.ResponseWriter, request *http.Request) {
	session, _ := store.Get(request, "session")

	switch request.Method {
	case "GET":
		auth, ok := session.Values["authenticated"].(bool)
		loggedIn := ok && auth

		questionRange, err := getQuestionRange()
		if err != nil {
			http.Error(writer, err.Error(), http.StatusInternalServerError)
			return
		}

		filteredQuestions := []Question{}
		for i := questionRange.Start; i < questionRange.End; i++ {
			storedQuestion, err := getStoredQuestion(i)
			if err != nil {
				http.Error(writer, err.Error(), http.StatusInternalServerError)
				return
			}

			if storedQuestion.Visibility != Deleted && (loggedIn || storedQuestion.Visibility == Visible) {
				voted, ok := session.Values[i].(bool)

				question := Question{
					Id:         int(i),
					Text:       storedQuestion.Text,
					Upvotes:    storedQuestion.Upvotes,
					Visibility: storedQuestion.Visibility,
					Upvoted:    ok && voted,
				}
				filteredQuestions = append(filteredQuestions, question)
			}
		}

		encoder := json.NewEncoder(writer)
		err = encoder.Encode(filteredQuestions)
		if err != nil {
			http.Error(writer, err.Error(), http.StatusInternalServerError)
			return
		}
	case "POST":
		var requestData AddQuestionRequest
		decoder := json.NewDecoder(request.Body)
		err := decoder.Decode(&requestData)

		if requestData.Text == "" {
			http.Error(writer, "Empty question", http.StatusBadRequest)
			return
		}

		if len(requestData.Text) > maxQuestionLen {
			http.Error(writer, "Question too large", http.StatusRequestEntityTooLarge)
			return
		}

		newLen, err := rdb.Incr(ctx, fmt.Sprintf("%vquestions-end", keyPrefix)).Result()
		if err != nil {
			http.Error(writer, err.Error(), http.StatusInternalServerError)
			return
		}

		id := newLen - 1
		key := fmt.Sprintf("%vquestion:%v", keyPrefix, id)
		err = rdb.HSet(ctx, key, "text", requestData.Text, "visibility", defaultVisibility, "upvotes", 0).Err()
		if err != nil {
			http.Error(writer, err.Error(), http.StatusInternalServerError)
			return
		}
	case "DELETE":
		if auth, ok := session.Values["authenticated"].(bool); !ok || !auth {
			http.Error(writer, "Forbidden", http.StatusForbidden)
			return
		}

		questionRange, err := getQuestionRange()
		if err != nil {
			http.Error(writer, err.Error(), http.StatusInternalServerError)
			return
		}

		err = rdb.Set(ctx, fmt.Sprintf("%vquestions-start", keyPrefix), questionRange.End, 0).Err()
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

	var requestData ModifyQuestionRequest
	decoder := json.NewDecoder(request.Body)
	err := decoder.Decode(&requestData)
	if err != nil {
		log.Printf("Error reading HTTP request, ignoring request: %v", err)
		return
	}

	id := requestData.Id
	if voted, ok := session.Values[id].(bool); !ok || !voted {
		questionRange, err := getQuestionRange()
		if err != nil {
			http.Error(writer, err.Error(), http.StatusInternalServerError)
			return
		}

		if !questionRange.validId(id) {
			http.Error(writer, "ID does not exist", http.StatusBadRequest)
			return
		}

		key := fmt.Sprintf("%vquestion:%v", keyPrefix, id)
		err = rdb.HIncrBy(ctx, key, "upvotes", 1).Err()
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

	var requestData ModifyQuestionRequest
	decoder := json.NewDecoder(request.Body)
	err := decoder.Decode(&requestData)

	id := requestData.Id

	questionRange, err := getQuestionRange()
	if err != nil {
		http.Error(writer, err.Error(), http.StatusInternalServerError)
		return
	}

	if !questionRange.validId(id) {
		http.Error(writer, "ID does not exist", http.StatusBadRequest)
		return
	}

	key := fmt.Sprintf("%vquestion:%v", keyPrefix, id)
	err = rdb.HSet(ctx, key, "visibility", visibility).Err()
	if err != nil {
		http.Error(writer, err.Error(), http.StatusInternalServerError)
		return
	}
}

func export(writer http.ResponseWriter, request *http.Request) {
	exportQuestions(writer, request, false)
}

func exportAll(writer http.ResponseWriter, request *http.Request) {
	exportQuestions(writer, request, true)
}

func exportQuestions(writer http.ResponseWriter, request *http.Request, includeHidden bool) {
	session, _ := store.Get(request, "session")

	if auth, ok := session.Values["authenticated"].(bool); !ok || !auth {
		http.Error(writer, "Forbidden", http.StatusForbidden)
		return
	}

	writer.Header().Set("Content-Disposition", "attachment; filename=\"questions.txt\"")

	questionRange, err := getQuestionRange()
	if err != nil {
		http.Error(writer, err.Error(), http.StatusInternalServerError)
		return
	}

	for i := questionRange.Start; i < questionRange.End; i++ {
		storedQuestion, err := getStoredQuestion(i)
		if err != nil {
			http.Error(writer, err.Error(), http.StatusInternalServerError)
			return
		}

		if storedQuestion.Visibility != Deleted && (includeHidden || storedQuestion.Visibility == Visible) {
			fmt.Fprintln(writer, storedQuestion.Text)
		}
	}
}
