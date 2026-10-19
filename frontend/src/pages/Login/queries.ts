import { useSessionMutation } from "@/session/queries";

export function useLogin() {
  return useSessionMutation("POST");
}
