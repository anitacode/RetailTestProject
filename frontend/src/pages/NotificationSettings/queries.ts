import { queryOptions, useMutation, useQueryClient } from "@tanstack/react-query";
import { request } from "@/api";
import { sessionKey } from "@/queryKeys";
import type { Contact, ContactInput, ContactsResponse } from "@/pages/NotificationSettings/types";
import type { SessionResponse } from "@/types";

export const contactsQuery = (brandId: number, page: number, keyword = "") =>
  queryOptions({
    queryKey: ["contacts", brandId, page, keyword],
    queryFn: ({ signal }) =>
      request<ContactsResponse>(`/contacts?page=${page}&q=${encodeURIComponent(keyword)}`, {
        signal,
      }),
  });

export function useSaveContact(brandId: number) {
  const client = useQueryClient();
  return useMutation({
    mutationFn: ({ id, contact }: { id?: number; contact: ContactInput }) =>
      request<{ contact: Contact }>(id ? `/contacts/${id}` : "/contacts", {
        method: id ? "PATCH" : "POST",
        body: JSON.stringify({ contact }),
      }),
    onSuccess: async () => {
      if (client.getQueryData<SessionResponse>(sessionKey)?.brand?.id !== brandId) return;
      await client.invalidateQueries({ queryKey: ["contacts", brandId] });
    },
  });
}

export const contactQuery = (brandId: number, id: string) =>
  queryOptions({
    queryKey: ["contacts", brandId, "detail", id],
    queryFn: ({ signal }) =>
      request<{ contact: Contact }>(`/contacts/${encodeURIComponent(id)}`, { signal }),
    staleTime: 0,
  });
