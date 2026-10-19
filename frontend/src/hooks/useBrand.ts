import { useQuery } from "@tanstack/react-query";
import { sessionQuery } from "@/session/queries";
import type { SessionResponse } from "@/types";

const selectBrand = (session: SessionResponse) => session.brand;

// Shares the session cache; undefined means loading, null means signed out.
export function useBrand() {
  return useQuery({ ...sessionQuery, select: selectBrand });
}
