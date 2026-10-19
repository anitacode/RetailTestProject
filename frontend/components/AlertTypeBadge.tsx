import Badge, { type BadgeVariant } from "@/ui/Badge";
import type { AlertType } from "@/types";

const alertTypes = {
  alert_no_inventory: { label: "Inventory alert", variant: "warning" },
  alert_price_change: { label: "Price change", variant: "info" },
} satisfies Record<AlertType, { label: string; variant: BadgeVariant }>;

export default function AlertTypeBadge({ type }: { type: AlertType }) {
  const { label, variant } = alertTypes[type];
  return <Badge variant={variant}>{label}</Badge>;
}
