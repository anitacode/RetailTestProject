let csrfToken: string | undefined;

export class ApiError extends Error {
  readonly status: number;

  constructor(message: string, status: number) {
    super(message);
    this.name = "ApiError";
    this.status = status;
  }
}

export function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : "Something went wrong. Please try again.";
}

export async function request<T>(path: string, options: RequestInit = {}): Promise<T> {
  const headers = new Headers({ Accept: "application/json", "Content-Type": "application/json" });
  if (csrfToken) headers.set("X-CSRF-Token", csrfToken);
  new Headers(options.headers).forEach((value, key) => headers.set(key, value));
  const response = await fetch(`/api${path}`, {
    ...options,
    credentials: "same-origin",
    headers,
  });
  let data: unknown;
  try {
    data = await response.json();
  } catch {
    throw new Error("The server could not complete the request. Please try again.");
  }
  options.signal?.throwIfAborted();
  if (!response.ok) {
    const message =
      data && typeof data === "object" && "error" in data && typeof data.error === "string"
        ? data.error
        : "Something went wrong. Please try again.";
    throw new ApiError(message, response.status);
  }
  if (
    data &&
    typeof data === "object" &&
    "csrf_token" in data &&
    typeof data.csrf_token === "string"
  ) {
    csrfToken = data.csrf_token;
  }
  // Response shapes follow the Rails contract; TypeScript does not validate server JSON at runtime.
  return data as T;
}

const dateFormatter = new Intl.DateTimeFormat(undefined, {
  dateStyle: "medium",
  timeStyle: "short",
});

export const dateTime = (value: string): string => dateFormatter.format(new Date(value));
