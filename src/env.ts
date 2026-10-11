import { defineEnvVars } from '@sveltejs/kit/env';

export const variables = defineEnvVars({
  PUBLIC_IMPRINT_URL: { public: true, static: true },
  PUBLIC_PRIVACY_POLICY_URL: { public: true, static: true }
});
