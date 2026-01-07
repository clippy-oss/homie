// Supabase Configuration - loaded from environment variables via Vite
const SUPABASE_URL = import.meta.env.VITE_SUPABASE_URL;
const SUPABASE_ANON_KEY = import.meta.env.VITE_SUPABASE_ANON_KEY;

// Initialize Supabase client
const { createClient } = supabase;
const supabaseClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

// Helper function to get current JWT token from Supabase session
async function getJWTToken() {
  try {
    const {
      data: { session },
      error,
    } = await supabaseClient.auth.getSession();
    if (error) {
      console.error("Error getting session:", error);
      return null;
    }
    return session?.access_token || null;
  } catch (error) {
    console.error("Error getting JWT token:", error);
    return null;
  }
}

// Helper function to get current user from Supabase session
async function getCurrentUserData() {
  try {
    const {
      data: { session },
      error,
    } = await supabaseClient.auth.getSession();
    if (error || !session) {
      return null;
    }

    const user = session.user;
    return {
      accountId: user.id,
      email: user.email,
      firstName:
        user.user_metadata?.full_name?.split(" ")[0] ||
        user.user_metadata?.first_name ||
        null,
      lastName:
        user.user_metadata?.full_name?.split(" ").slice(1).join(" ") ||
        user.user_metadata?.last_name ||
        null,
      phoneNumber: user.phone || user.user_metadata?.phone_number || null,
      jwtToken: session.access_token,
    };
  } catch (error) {
    console.error("Error getting current user data:", error);
    return null;
  }
}

// Clear ALL authentication data and sign out
async function clearUserData() {
  // Sign out from Supabase (this will clear Supabase's session storage automatically)
  try {
    const { error } = await supabaseClient.auth.signOut();
    if (error) {
      console.error("Error during Supabase sign out:", error);
    }
  } catch (error) {
    console.error("Error signing out:", error);
  }

  // Clear legacy custom user data (cleanup for users upgrading from old version)
  localStorage.removeItem("clippy_user_data");
  localStorage.removeItem("jwt_token");
  localStorage.removeItem("user");
  localStorage.removeItem("token");

  console.log("All authentication data cleared");
}

// Phone number sanitization utility function
function sanitizePhoneNumberForStorage(phoneNumber) {
  // Remove all non-digit characters except + at the beginning
  let cleaned = phoneNumber.replace(/[^\d+]/g, "");

  // Ensure it starts with +
  if (!cleaned.startsWith("+")) {
    // If it starts with 00, convert to +
    if (cleaned.startsWith("00")) {
      cleaned = "+" + cleaned.substring(2);
    } else {
      // Assume it needs a + prefix
      cleaned = "+" + cleaned;
    }
  }

  // Remove duplicate country codes (e.g., +49+49 or +490049)
  cleaned = removeDuplicateCountryCode(cleaned);

  return cleaned;
}

// Remove duplicate country codes from phone number
function removeDuplicateCountryCode(phoneNumber) {
  if (!phoneNumber.startsWith("+")) {
    return phoneNumber;
  }

  // Extract the potential country code (1-4 digits after +)
  const match = phoneNumber.match(/^\+(\d{1,4})/);
  if (!match) {
    return phoneNumber;
  }

  const countryCode = match[1];
  const restOfNumber = phoneNumber.substring(match[0].length);

  // Check if the rest starts with the same country code
  // Pattern 1: +49+49123... or +4949123...
  if (
    restOfNumber.startsWith("+" + countryCode) ||
    restOfNumber.startsWith(countryCode)
  ) {
    // Remove the duplicate
    const cleanedRest = restOfNumber.replace(
      new RegExp(`^\\+?${countryCode}`),
      ""
    );
    return "+" + countryCode + cleanedRest;
  }

  // Pattern 2: +4900491234... (country code followed by 00 + country code)
  if (restOfNumber.startsWith("00" + countryCode)) {
    const cleanedRest = restOfNumber.substring(("00" + countryCode).length);
    return "+" + countryCode + cleanedRest;
  }

  return phoneNumber;
}

// Clean phone number input by removing any leading country code prefix
function cleanPhoneNumberInput(phoneNumber, countryCode) {
  // Remove all non-digit characters except + at the beginning
  let cleaned = phoneNumber.trim().replace(/[^\d+]/g, "");

  // Remove leading + if present
  if (cleaned.startsWith("+")) {
    cleaned = cleaned.substring(1);
  }

  // Remove leading 00 if present (international dialing prefix)
  if (cleaned.startsWith("00")) {
    cleaned = cleaned.substring(2);
  }

  // Extract the country code without the + sign
  const countryCodeDigits = countryCode.replace("+", "");

  // If the cleaned number starts with the country code, remove it
  if (cleaned.startsWith(countryCodeDigits)) {
    cleaned = cleaned.substring(countryCodeDigits.length);
  }

  // Remove leading 0 from local number (trunk prefix used in domestic dialing)
  // This is common in many countries (Germany, UK, France, etc.)
  // where local numbers start with 0 but this should be omitted in international format
  while (cleaned.startsWith("0")) {
    cleaned = cleaned.substring(1);
  }

  return cleaned;
}

// Generate multiple phone number variations for checking duplicates
function generatePhoneVariations(phoneNumber) {
  const variations = new Set();

  // Add the original number
  variations.add(phoneNumber);

  // Add sanitized version
  variations.add(sanitizePhoneNumberForStorage(phoneNumber));

  // If number starts with +, also add without +
  if (phoneNumber.startsWith("+")) {
    const withoutPlus = phoneNumber.substring(1);
    variations.add(withoutPlus);
    variations.add("00" + withoutPlus);
  }

  // If number doesn't start with +, add with +
  if (!phoneNumber.startsWith("+")) {
    variations.add("+" + phoneNumber);
    if (phoneNumber.startsWith("00")) {
      variations.add("+" + phoneNumber.substring(2));
    }
  }

  return Array.from(variations);
}

// Voice Pipeline API Configuration - loaded from environment variables via Vite
const VOICE_PIPELINE_URL =
  import.meta.env.VITE_VOICE_PIPELINE_URL || "http://localhost:7860";

// API request helper - automatically includes JWT from Supabase session
async function apiRequest(
  endpoint,
  method = "GET",
  body = null,
  jwtToken = null,
  timeoutMs = 10000 // Default 10 second timeout
) {
  const options = {
    method,
    headers: {
      "Content-Type": "application/json",
    },
  };

  // Get JWT token from Supabase session if not provided
  if (!jwtToken) {
    jwtToken = await getJWTToken();
  }

  // Add JWT token if available
  if (jwtToken) {
    options.headers["Authorization"] = `Bearer ${jwtToken}`;
  }

  if (body) {
    options.body = JSON.stringify(body);
  }

  // Create abort controller for timeout
  const controller = new AbortController();
  options.signal = controller.signal;

  // Set timeout
  const timeoutId = setTimeout(() => controller.abort(), timeoutMs);

  try {
    const response = await fetch(`${VOICE_PIPELINE_URL}${endpoint}`, options);
    clearTimeout(timeoutId);

    const data = await response.json();

    if (!response.ok) {
      throw new Error(data.detail || data.message || "API request failed");
    }

    return data;
  } catch (error) {
    clearTimeout(timeoutId);
    if (error.name === "AbortError") {
      throw new Error(`Request timeout after ${timeoutMs}ms`);
    }
    throw error;
  }
}

// Function to fetch service status
async function fetchServiceStatus(accountId) {
  try {
    // JWT token will be automatically retrieved from Supabase session by apiRequest
    const data = await apiRequest(
      `/service-status?account_id=${encodeURIComponent(accountId)}`,
      "GET"
    );
    return { success: true, data: data };
  } catch (error) {
    console.error("Error fetching service status:", error);
    return { success: false, error: error.message };
  }
}

// Supabase Auth Functions
// Sign up user with email and password
async function signUpUser(email, password, userMetadata = {}) {
  try {
    const { data, error } = await supabaseClient.auth.signUp({
      email: email,
      password: password,
      options: {
        data: userMetadata,
      },
    });

    if (error) {
      console.error("Error signing up user:", error);
      return { success: false, error: error.message };
    }

    console.log("User signed up successfully:", data);
    return { success: true, data: data };
  } catch (error) {
    console.error("Unexpected error:", error);
    return { success: false, error: error.message };
  }
}

// Sign in user with email and password
async function signInUser(email, password) {
  try {
    const { data, error } = await supabaseClient.auth.signInWithPassword({
      email: email,
      password: password,
    });

    if (error) {
      console.error("Error signing in user:", error);
      return { success: false, error: error.message };
    }

    console.log("User signed in successfully:", data);
    return { success: true, data: data };
  } catch (error) {
    console.error("Unexpected error:", error);
    return { success: false, error: error.message };
  }
}

// Sign out user
async function signOutUser() {
  try {
    const { error } = await supabaseClient.auth.signOut();
    if (error) {
      console.error("Error signing out user:", error);
      return { success: false, error: error.message };
    }
    console.log("User signed out successfully");
    return { success: true };
  } catch (error) {
    console.error("Unexpected error:", error);
    return { success: false, error: error.message };
  }
}

// Get current user session
async function getCurrentUser() {
  try {
    const {
      data: { user },
      error,
    } = await supabaseClient.auth.getUser();
    if (error) {
      console.error("Error getting current user:", error);
      return { success: false, error: error.message };
    }
    return { success: true, user: user };
  } catch (error) {
    console.error("Unexpected error:", error);
    return { success: false, error: error.message };
  }
}

// Check if JWT token is valid (not expired)
function isJWTValid(jwtToken) {
  if (!jwtToken) {
    return false;
  }

  try {
    // Decode JWT token (without verification, just to check expiry)
    const parts = jwtToken.split(".");
    if (parts.length !== 3) {
      return false;
    }

    // Decode payload
    const payload = JSON.parse(atob(parts[1]));

    // Check if token has expired
    if (payload.exp) {
      const expiryTime = payload.exp * 1000; // Convert to milliseconds
      const currentTime = Date.now();

      if (currentTime >= expiryTime) {
        console.log("JWT token has expired");
        return false;
      }
    }

    return true;
  } catch (error) {
    console.error("Error validating JWT token:", error);
    return false;
  }
}

// Verify JWT token with server
async function verifyTokenWithServer(jwtToken) {
  try {
    const response = await fetch(
      `${VOICE_PIPELINE_URL}/auth/phone/verify-token`,
      {
        method: "GET",
        headers: {
          Authorization: `Bearer ${jwtToken}`,
          "Content-Type": "application/json",
        },
      }
    );

    if (response.ok) {
      const data = await response.json();
      return data.valid === true;
    }

    return false;
  } catch (error) {
    console.error("Error verifying token with server:", error);
    return false;
  }
}

// Check if user is already authenticated and redirect to dashboard
async function checkAuthAndRedirect(redirectToDashboard = true) {
  const currentUser = await getCurrentUserData();

  if (!currentUser) {
    return false;
  }

  // Verify token with server
  console.log("Verifying JWT token with server...");
  const isValid = await verifyTokenWithServer(currentUser.jwtToken);

  if (isValid) {
    console.log("User already authenticated with valid JWT token");

    if (redirectToDashboard) {
      console.log("Redirecting to dashboard...");
      window.location.href = "dashboard.html";
    }

    return true;
  }

  // Invalid token - sign out
  await clearUserData();
  return false;
}

// Function to generate session ID in format: phone_(countrycodewithoutplusandnumber)
function generateSessionId(countryCode, phoneNumber) {
  if (!countryCode || !phoneNumber) {
    console.error(
      "Missing country code or phone number for session ID generation"
    );
    return "phone_unknown";
  }

  // Remove the + from country code and combine with phone number
  const countryCodeWithoutPlus = countryCode.replace("+", "");
  return `phone_${countryCodeWithoutPlus}${phoneNumber}`;
}

// Sign up user with complete data in one request - NEW UNIFIED API
async function signUpWithAllData(
  phoneNumber,
  firstName,
  lastName,
  email,
  password
) {
  try {
    const sanitizedPhoneNumber = sanitizePhoneNumberForStorage(phoneNumber);

    console.log(
      "Signing up user with complete data - phone:",
      sanitizedPhoneNumber,
      "email:",
      email
    );

    // Call voice-pipeline unified signup API
    const result = await apiRequest("/auth/phone/signup", "POST", {
      phone_number: sanitizedPhoneNumber,
      first_name: firstName,
      last_name: lastName,
      email: email,
      password: password,
    });

    if (result.success) {
      console.log("User signed up successfully:", result);
      return {
        success: true,
        data: {
          account_id: result.account_id,
          phone_number: result.phone_number,
          email: result.email,
          first_name: result.first_name,
          last_name: result.last_name,
        },
        jwt_token: result.jwt_token,
      };
    } else {
      console.error("Error signing up user:", result.message);
      return { success: false, error: result.message };
    }
  } catch (error) {
    console.error("Unexpected error during signup:", error);
    return { success: false, error: error.message };
  }
}

// DEPRECATED - Create user with just phone number (Step 1) - OLD API VERSION
async function createUserWithPhone(countryCode, phoneNumber) {
  try {
    const fullPhoneNumber = countryCode + phoneNumber;
    const sanitizedPhoneNumber = sanitizePhoneNumberForStorage(fullPhoneNumber);

    console.log("Creating user via API for phone:", sanitizedPhoneNumber);

    // Call voice-pipeline API to create user via Admin API
    const result = await apiRequest("/auth/phone/create-user", "POST", {
      phone_number: sanitizedPhoneNumber,
    });

    if (result.status === "success") {
      console.log("User created via API successfully:", result);
      return {
        success: true,
        data: {
          id: null, // Not used anymore, account_id is the primary identifier
          account_id: result.account_id,
          phone_number: result.phone_number,
        },
      };
    } else {
      console.error("Error creating user via API:", result.message);
      return { success: false, error: result.message };
    }
  } catch (error) {
    console.error("Unexpected error calling API:", error);
    return { success: false, error: error.message };
  }
}

// Update user with name data (Step 2) - NEW API VERSION
async function updateUserWithName(accountId, firstName, lastName) {
  try {
    console.log(
      "Updating user name via API - accountId:",
      accountId,
      "firstName:",
      firstName,
      "lastName:",
      lastName
    );

    // Call voice-pipeline API to update name
    const result = await apiRequest("/auth/phone/update-name", "POST", {
      account_id: accountId,
      first_name: firstName,
      last_name: lastName,
    });

    if (result.status === "success") {
      console.log("Name updated via API successfully");
      return {
        success: true,
        data: {
          account_id: accountId,
          first_name: firstName,
          last_name: lastName,
        },
      };
    } else {
      console.error("Error updating name via API:", result.message);
      return { success: false, error: result.message };
    }
  } catch (error) {
    console.error("Unexpected error calling API:", error);
    return { success: false, error: error.message };
  }
}

// Update user with email (Step 3) - NEW API VERSION
async function updateUserWithEmail(accountId, email) {
  try {
    console.log(
      "Updating user email via API - accountId:",
      accountId,
      "email:",
      email
    );

    // Call voice-pipeline API to update email (includes duplicate check)
    const result = await apiRequest("/auth/phone/update-email", "POST", {
      account_id: accountId,
      email: email,
    });

    if (result.status === "success") {
      console.log("Email updated via API successfully");
      return {
        success: true,
        data: { account_id: accountId, email: email },
      };
    } else {
      console.error("Error updating email via API:", result.message);
      return { success: false, error: result.message };
    }
  } catch (error) {
    console.error("Unexpected error calling API:", error);
    return { success: false, error: error.message };
  }
}

// Update user with password (Step 4) - NEW API VERSION
async function updateUserWithPassword(accountId, password) {
  try {
    console.log("Setting user password via API - accountId:", accountId);

    // Call voice-pipeline API to set password via Admin API
    const result = await apiRequest("/auth/phone/set-password", "POST", {
      account_id: accountId,
      password: password,
    });

    if (result.status === "success") {
      console.log("Password set via API successfully");
      return {
        success: true,
        data: { account_id: accountId },
        message: result.message,
      };
    } else {
      console.error("Error setting password via API:", result.message);
      return { success: false, error: result.message };
    }
  } catch (error) {
    console.error("Unexpected error calling API:", error);
    return { success: false, error: error.message };
  }
}

// Function to check if user already exists - calls backend API
async function checkUserExists(phoneNumber, email) {
  try {
    const sanitizedPhoneNumber = phoneNumber
      ? sanitizePhoneNumberForStorage(phoneNumber)
      : null;

    console.log(
      "Checking if user exists - phone:",
      sanitizedPhoneNumber,
      "email:",
      email
    );

    // Call voice-pipeline API to check user existence (uses service role, bypasses RLS)
    const result = await apiRequest(
      "/auth/phone/check-user",
      "POST",
      {
        phone_number: sanitizedPhoneNumber,
        email: email,
      },
      null
    ); // No JWT needed for this endpoint

    if (result.success !== undefined) {
      return {
        success: true,
        exists: result.exists,
        user: result.user || null,
      };
    } else {
      console.error("Error checking user:", result.message);
      return { success: false, error: result.message };
    }
  } catch (error) {
    console.error("Unexpected error checking user:", error);
    return { success: false, error: error.message };
  }
}

// Function to check if user has complete profile
function hasCompleteProfile(user) {
  return (
    user && user.first_name && user.last_name && user.email && user.auth_user_id
  );
}

// Function to update existing user
async function updateUser(userId, updateData) {
  try {
    console.log("Updating user - userId:", userId, "updateData:", updateData);

    const { data, error } = await supabaseClient
      .from("users")
      .update(updateData)
      .eq("id", userId)
      .select();

    if (error) {
      console.error("Error updating user:", error);
      return { success: false, error: error.message };
    }

    console.log("Update result - data:", data);

    // Check if the update actually affected any rows
    if (!data || data.length === 0) {
      console.warn(
        "Update succeeded but no data returned. Fetching user separately..."
      );
      const { data: userData, error: fetchError } = await supabaseClient
        .from("users")
        .select("*")
        .eq("id", userId)
        .single();

      if (fetchError) {
        console.error("Error fetching updated user:", fetchError);
        return { success: true, data: { id: userId, ...updateData } };
      }

      console.log("Fetched user after update:", userData);
      return { success: true, data: userData };
    }

    console.log("User updated successfully:", data);
    return { success: true, data: data[0] };
  } catch (error) {
    console.error("Unexpected error:", error);
    return { success: false, error: error.message };
  }
}

// Export commonly used functions for use in other modules
export {
  supabaseClient,
  VOICE_PIPELINE_URL,
  getJWTToken,
  getCurrentUserData,
  clearUserData,
  sanitizePhoneNumberForStorage,
  cleanPhoneNumberInput,
  generatePhoneVariations,
  apiRequest,
  fetchServiceStatus,
  signUpUser,
  signInUser,
  signOutUser,
  getCurrentUser,
  isJWTValid,
  verifyTokenWithServer,
  checkAuthAndRedirect,
  generateSessionId,
  signUpWithAllData,
  createUserWithPhone,
  updateUserWithName,
  updateUserWithEmail,
  updateUserWithPassword,
  checkUserExists,
  hasCompleteProfile,
  updateUser,
};
