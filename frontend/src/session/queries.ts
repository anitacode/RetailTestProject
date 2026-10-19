import { queryOptions, useMutation, useQueryClient } from "@tanstack/react-query";
import { request } from "@/api";
import { sessionKey, alertsKey } from "@/queryKeys";
import type { SessionResponse } from "@/types";

export const sessionQuery = queryOptions({
  queryKey: sessionKey,
  queryFn: ({ signal }) => request<SessionResponse>("/session", { signal }),
  staleTime: Infinity,
});

export function useSessionMutation(method: "POST" | "DELETE") {
  const client = useQueryClient();
  return useMutation({
    mutationFn: (name?: string) =>
      request<SessionResponse>("/session", {
        method,
        ...(method === "POST" ? { body: JSON.stringify({ name }) } : {}),
      }),
    // A session response from an earlier GET must not overwrite a login/logout.
    onMutate: () => client.cancelQueries({ queryKey: sessionKey }),
    onSuccess: async (session) => {
      await client.cancelQueries({ queryKey: alertsKey });
      await client.cancelQueries({ queryKey: ["contacts"] });
      await client.cancelQueries({ queryKey: ["jobs"] });
      await client.cancelQueries({ queryKey: ["trackingEvents"] });
      client.removeQueries({ queryKey: ["trackingEvents"] });
      client.removeQueries({ queryKey: ["jobs"] });
      client.removeQueries({ queryKey: ["contacts"] });
      client.removeQueries({ queryKey: alertsKey });
      client.setQueryData(sessionKey, session);
    },
  });
}
