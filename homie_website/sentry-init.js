/**
 * Sentry initialization for Clippy website
 *
 * This must be loaded BEFORE any other JavaScript files
 */

(function() {
    // Get Sentry DSN from environment or inline config
    const SENTRY_DSN = window.SENTRY_DSN || 'YOUR_SENTRY_DSN_HERE';
    const ENVIRONMENT = window.location.hostname === 'localhost' || window.location.hostname === '127.0.0.1'
        ? 'development'
        : 'production';

    if (!SENTRY_DSN || SENTRY_DSN === 'YOUR_SENTRY_DSN_HERE') {
        console.warn('⚠️ Sentry DSN not configured - error tracking disabled');
        return;
    }

    // Initialize Sentry
    Sentry.init({
        dsn: SENTRY_DSN,
        environment: ENVIRONMENT,
        integrations: [
            Sentry.browserTracingIntegration(),
            Sentry.replayIntegration({
                maskAllText: true,
                blockAllMedia: true,
            }),
        ],

        // Performance Monitoring
        tracesSampleRate: ENVIRONMENT === 'production' ? 0.1 : 1.0, // 10% in prod, 100% in dev

        // Session Replay
        replaysSessionSampleRate: 0.1, // 10% of sessions
        replaysOnErrorSampleRate: 1.0, // 100% of sessions with errors

        // Sanitize PII before sending
        beforeSend(event, hint) {
            // Remove sensitive data from breadcrumbs
            if (event.breadcrumbs) {
                event.breadcrumbs = event.breadcrumbs.map(breadcrumb => {
                    if (breadcrumb.data) {
                        // Redact password fields
                        if (breadcrumb.data.password) {
                            breadcrumb.data.password = '[REDACTED]';
                        }
                        // Redact token fields
                        if (breadcrumb.data.token) {
                            breadcrumb.data.token = '[REDACTED]';
                        }
                        // Mask email addresses
                        if (breadcrumb.data.email && breadcrumb.data.email.includes('@')) {
                            const parts = breadcrumb.data.email.split('@');
                            breadcrumb.data.email = `${parts[0].substring(0, 3)}***@${parts[1]}`;
                        }
                    }
                    return breadcrumb;
                });
            }

            // Remove sensitive data from request
            if (event.request && event.request.data) {
                const sensitiveFields = ['password', 'token', 'api_key', 'otp'];
                sensitiveFields.forEach(field => {
                    if (event.request.data[field]) {
                        event.request.data[field] = '[REDACTED]';
                    }
                });
            }

            return event;
        },

        // Tag service
        initialScope: {
            tags: {
                service: 'clippy-website'
            }
        }
    });

    console.log(`✅ Sentry initialized - Environment: ${ENVIRONMENT}`);

    // Helper function to set user context (call after login)
    window.setSentryUser = function(userData) {
        if (!userData) {
            Sentry.setUser(null);
            return;
        }

        const user = {
            id: userData.accountId || userData.account_id
        };

        // Partially mask phone number
        if (userData.phoneNumber || userData.phone_number) {
            const phone = userData.phoneNumber || userData.phone_number;
            if (phone.length > 4) {
                user.phone = '****' + phone.slice(-4);
            }
        }

        // Partially mask email
        if (userData.email && userData.email.includes('@')) {
            const parts = userData.email.split('@');
            user.email = `${parts[0].substring(0, 3)}***@${parts[1]}`;
        }

        Sentry.setUser(user);
    };

    // Helper function to add breadcrumbs
    window.addSentryBreadcrumb = function(message, category, data) {
        Sentry.addBreadcrumb({
            message: message,
            category: category || 'user-action',
            level: 'info',
            data: data || {}
        });
    };

    // Helper function to capture custom errors
    window.captureSentryError = function(error, context) {
        Sentry.captureException(error, {
            tags: context?.tags || {},
            extra: context?.extra || {}
        });
    };

    // Automatically track navigation
    const originalPushState = history.pushState;
    history.pushState = function() {
        const url = arguments[2];
        window.addSentryBreadcrumb(`Navigation to ${url}`, 'navigation', { url: url });
        return originalPushState.apply(history, arguments);
    };

    // Track page load
    window.addEventListener('load', function() {
        window.addSentryBreadcrumb('Page loaded', 'navigation', {
            url: window.location.href
        });
    });

    // Track unhandled promise rejections
    window.addEventListener('unhandledrejection', function(event) {
        console.error('Unhandled promise rejection:', event.reason);
        Sentry.captureException(event.reason, {
            tags: { type: 'unhandled_promise_rejection' }
        });
    });

})();
