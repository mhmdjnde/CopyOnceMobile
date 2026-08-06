import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";

/**
 * Refreshes the Supabase session on every request and keeps signed-out visitors
 * out of the app.
 *
 * Renamed from `middleware` in Next 16; the runtime is Node and cannot be
 * changed. The export must be `config`, not `proxyConfig`.
 *
 * This is an *optimistic* gate only. It checks that a session exists — it does
 * not decide what that session may read. Authorization lives in Row Level
 * Security, and the two-factor assurance check happens in the app layout where
 * it can be awaited properly. Never treat a proxy check as the security
 * boundary.
 */
export async function proxy(request: NextRequest) {
  let response = NextResponse.next({ request });

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!,
    {
      cookies: {
        getAll() {
          return request.cookies.getAll();
        },
        setAll(cookiesToSet) {
          for (const { name, value } of cookiesToSet) {
            request.cookies.set(name, value);
          }
          response = NextResponse.next({ request });
          for (const { name, value, options } of cookiesToSet) {
            response.cookies.set(name, value, options);
          }
        },
      },
    },
  );

  // getUser() revalidates the token with Supabase rather than trusting the
  // cookie's contents. getSession() would be faster and forgeable.
  const {
    data: { user },
  } = await supabase.auth.getUser();

  const { pathname } = request.nextUrl;

  // Route handlers authenticate themselves and answer with status codes, not
  // redirects. Sending an API call to the sign-in page turns "not configured"
  // into a 307 that no client can interpret — which is exactly what the QR
  // endpoints hit, since they are meant to be called before there is a session.
  if (pathname.startsWith("/api/")) return response;

  const isPublic =
    pathname === "/" ||
    pathname.startsWith("/sign-in") ||
    pathname.startsWith("/sign-up") ||
    pathname.startsWith("/verify") ||
    pathname.startsWith("/forgot-password") ||
    pathname.startsWith("/reset-password") ||
    pathname.startsWith("/auth");

  if (!user && !isPublic) {
    const signIn = request.nextUrl.clone();
    signIn.pathname = "/sign-in";
    // So the user lands back where they were aiming after signing in.
    signIn.searchParams.set("next", pathname);
    return NextResponse.redirect(signIn);
  }

  // Someone already signed in has no use for the sign-in page.
  if (user && (pathname === "/sign-in" || pathname === "/sign-up")) {
    const app = request.nextUrl.clone();
    app.pathname = "/clipboard";
    app.search = "";
    return NextResponse.redirect(app);
  }

  return response;
}

export const config = {
  matcher: [
    /*
     * Everything except static assets and image files — running this on every
     * icon request would triple the auth traffic for no benefit.
     */
    "/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp|ico)$).*)",
  ],
};
