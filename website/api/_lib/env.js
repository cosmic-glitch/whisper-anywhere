const TRUE_VALUES = new Set(["1", "true", "yes", "on"]);

function env(name, fallback = "") {
  const value = process.env[name];
  if (typeof value === "string") {
    return value.trim();
  }
  return fallback;
}

function requiredEnv(name) {
  const value = env(name);
  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}

function envBool(name, fallback = false) {
  const value = env(name);
  if (!value) {
    return fallback;
  }
  return TRUE_VALUES.has(value.toLowerCase());
}

function envNumber(name, fallback) {
  const value = env(name);
  if (!value) {
    return fallback;
  }

  const parsed = Number(value);
  if (!Number.isFinite(parsed)) {
    return fallback;
  }

  return parsed;
}

export function loadConfig() {
  const googleAuthRedirectURI = env("GOOGLE_AUTH_REDIRECT_URI", "whisperanywhere://auth/callback");
  const authStartIPWindowDefault = Math.max(30, Math.floor(envNumber("OTP_IP_WINDOW_SECONDS", 600)));
  const authStartIPLimitDefault = Math.max(1, Math.floor(envNumber("OTP_IP_LIMIT", 10)));

  return {
    openAIAPIKey: requiredEnv("OPENAI_API_KEY"),
    supabaseURL: requiredEnv("SUPABASE_URL"),
    supabaseAnonKey: requiredEnv("SUPABASE_ANON_KEY"),
    supabaseServiceRoleKey: requiredEnv("SUPABASE_SERVICE_ROLE_KEY"),
    googleAuthRedirectURI,
    authStartIPWindowSeconds: Math.max(30, Math.floor(envNumber("AUTH_START_IP_WINDOW_SECONDS", authStartIPWindowDefault))),
    authStartIPLimit: Math.max(1, Math.floor(envNumber("AUTH_START_IP_LIMIT", authStartIPLimitDefault))),
    deepgramAPIKey: env("DEEPGRAM_API_KEY"),
  };
}
