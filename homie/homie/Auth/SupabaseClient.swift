//
//  SupabaseClient.swift
//  homie
//
//  Shared Supabase client instance
//

import Foundation
import Supabase

/// Shared Supabase client instance
/// SDK uses KeychainLocalStorage by default on macOS - no custom config needed
let supabase = SupabaseClient(
    supabaseURL: URL(string: Config.supabaseURL)!,
    supabaseKey: Config.supabaseAnonKey,
    options: SupabaseClientOptions(
        auth: SupabaseClientOptions.AuthOptions(
            // Emit local session immediately instead of waiting for refresh
            // See: https://github.com/supabase/supabase-swift/pull/822
            emitLocalSessionAsInitialSession: true
        )
    )
)
