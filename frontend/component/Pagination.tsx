interface PaginationProps {
  page: number;
  pages: number;
  onPageChange: (page: number) => void;
}

export default function Pagination({ page, pages, onPageChange }: PaginationProps) {
  return (
    <div className="flex items-center justify-between gap-2.5 border-t border-slate-200 p-3 text-sm text-slate-500">
      <span>
        Page {page} of {pages}
      </span>
      <div className="flex gap-2">
        <button
          type="button"
          className="rounded-[7px] border border-solid border-slate-200 bg-white px-[11px] py-[7px] text-[11px] text-slate-700 hover:enabled:bg-slate-100"
          disabled={page <= 1}
          onClick={() => onPageChange(page - 1)}
        >
          ← Previous
        </button>
        <button
          type="button"
          className="rounded-[7px] border border-solid border-slate-200 bg-white px-[11px] py-[7px] text-[11px] text-slate-700 hover:enabled:bg-slate-100"
          disabled={page >= pages}
          onClick={() => onPageChange(page + 1)}
        >
          Next →
        </button>
      </div>
    </div>
  );
}
