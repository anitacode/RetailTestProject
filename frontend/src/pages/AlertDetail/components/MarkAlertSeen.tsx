import InfoMessage from "@/ui/InfoMessage";
import { useEffect } from "react";
import { useMarkAlertSeen } from "@/pages/AlertDetail/queries";
import { errorMessage } from "@/api";

interface MarkAlertSeenProps {
  brandId: number;
  alertId: number;
}

export default function MarkAlertSeen({ brandId, alertId }: MarkAlertSeenProps) {
  const { mutate, error, isPending } = useMarkAlertSeen(brandId);
  useEffect(() => {
    mutate(alertId);
  }, [alertId, mutate]);

  if (!error) return null;
  return (
    <div className="text-center">
      <InfoMessage
        message={`Could not mark this alert as seen: ${errorMessage(error)}`}
        variant="error"
      />
      <button
        type="button"
        className="ml-3 underline disabled:opacity-45"
        onClick={() => mutate(alertId)}
        disabled={isPending}
      >
        Retry marking as seen
      </button>
    </div>
  );
}
