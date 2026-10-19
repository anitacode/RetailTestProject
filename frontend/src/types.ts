export interface Brand {
  id: number;
  name: string;
}

export interface SessionResponse {
  brand: Brand | null;
  csrf_token: string;
}

export interface Pagination {
  page: number;
  per_page: number;
  total: number;
  pages: number;
}
