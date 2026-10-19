import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import AlertTypeBadge from "@/ui/AlertTypeBadge";

describe("AlertTypeBadge", () => {
  it("labels inventory alerts", () => {
    render(<AlertTypeBadge type="alert_no_inventory" />);
    expect(screen.getByText("Inventory alert")).toBeInTheDocument();
  });

  it("labels price alerts without inventory copy", () => {
    render(<AlertTypeBadge type="alert_price_change" />);
    expect(screen.getByText("Price change")).toBeInTheDocument();
    expect(screen.queryByText("Inventory alert")).not.toBeInTheDocument();
  });
});
