import { QueryCache, QueryClient } from "@tanstack/react-query";
import { ApiError } from "@/api";
import { sessionKey, alertsKey } from "@/queryKeys";
import type { SessionResponse } from "@/types";

export function createQueryClient() {
  const client = new QueryClient({
    queryCache: new QueryCache({
      onError(error, query) {
        if (
          error instanceof ApiError &&
          error.status === 401 &&
          ["alerts", "contacts", "jobs", "trackingEvents"].includes(String(query.queryKey[0]))
        ) {
          const session = client.getQueryData<SessionResponse>(sessionKey);
          if (query.queryKey[1] !== session?.brand?.id) return;
          void client.cancelQueries({ queryKey: alertsKey });
          void client.cancelQueries({ queryKey: ["contacts"] });
          void client.cancelQueries({ queryKey: ["jobs"] });
          void client.cancelQueries({ queryKey: ["trackingEvents"] });
          client.removeQueries({ queryKey: ["trackingEvents"] });
          client.removeQueries({ queryKey: ["jobs"] });
          client.removeQueries({ queryKey: ["contacts"] });
          client.removeQueries({ queryKey: alertsKey });
          client.setQueryData<SessionResponse>(sessionKey, {
            brand: null,
            csrf_token: session?.csrf_token ?? "",
          });
        }
      },
    }),
    defaultOptions: {
      queries: {
        staleTime: 30_000,
        retry: (attempt, error) =>
          !(error instanceof ApiError && error.status < 500) && attempt < 1,
      },
      mutations: { retry: false },
    },
  });
  return client;
}
