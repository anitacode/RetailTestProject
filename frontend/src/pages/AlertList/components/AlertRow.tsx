import AlertTypeBadge from "@/ui/AlertTypeBadge";
import { Link } from "react-router-dom";
import { dateTime } from "@/api";
import type { Alert } from "@/pages/AlertList/types";

interface AlertRowProps {
  alert: Alert;
}

export default function AlertRow({ alert }: AlertRowProps) {
  return (
    <tr>
      <td className="px-[25px] py-5 text-[12px] max-lg:px-4 [tr:hover_&]:bg-slate-50">
        <Link className="text-[13px] font-semibold hover:underline" to={`/${alert.id}`}>
          {alert.product.name}
        </Link>
        {alert.seen_at === null && (
          <span className="ml-2 inline-block rounded-full border border-solid border-teal-200 bg-teal-50 px-2 py-0.5 text-[10px] font-semibold whitespace-nowrap text-teal-800">
            New
          </span>
        )}
        <span className="mt-[5px] block max-w-87.5 text-[11px] text-slate-500">
          {alert.store.address}
        </span>
      </td>
      <td className="px-[25px] py-5 text-[12px] max-lg:px-4 [tr:hover_&]:bg-slate-50">
        <AlertTypeBadge type={alert.alert_type} />
      </td>
      <td className="px-[25px] py-5 text-[11px] whitespace-nowrap text-slate-500 max-lg:px-4 [tr:hover_&]:bg-slate-50">
        {dateTime(alert.observed_at)}
      </td>
      <td className="px-[25px] py-5 text-[12px] max-lg:px-4 [tr:hover_&]:bg-slate-50">
        <Link
          className="grid h-[27px] w-[27px] place-items-center rounded-md border border-solid border-slate-200 text-slate-500"
          to={`/${alert.id}`}
          aria-label={`View alert for ${alert.product.name}`}
        >
          ↗
        </Link>
      </td>
    </tr>
  );
}
