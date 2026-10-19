import InfoMessage from "@/ui/InfoMessage";
import TrackingEvents from "@/pages/TrackingEvents/TrackingEvents";
import QueueStatus from "@/pages/QueueStatus/QueueStatus";
import NotificationSettings from "@/pages/NotificationSettings/NotificationSettings";
import { Navigate, Route, Routes, useLocation } from "react-router-dom";
import { errorMessage } from "@/api";
import { useBrand } from "@/hooks/useBrand";
import SideMenu from "@/component/SideMenu";
import Login from "@/pages/Login/Login";
import AlertList from "@/pages/AlertList/AlertList";
import AlertDetail from "@/pages/AlertDetail/AlertDetail";

export default function App() {
  const { pathname } = useLocation();
  const isTablePage =
    pathname === "/" ||
    pathname === "/settings" ||
    pathname.startsWith("/settings/") ||
    pathname === "/jobs" ||
    pathname === "/jobs/" ||
    pathname === "/tracking-events" ||
    pathname === "/tracking-events/";
  const session = useBrand();
  const brand = session.data;
  const error = session.error ? errorMessage(session.error) : "";

  if (!brand) return <Login />;
  return (
    <div
      className={`grid grid-cols-[240px_1fr] max-lg:grid-cols-[200px_1fr] max-md:grid-cols-1 max-md:grid-rows-[auto_1fr] ${isTablePage ? "h-dvh overflow-hidden" : "min-h-dvh"}`}
    >
      <SideMenu />
      <div className="flex min-h-0 min-w-0 flex-col">
        <main className="mx-auto flex min-h-0 w-full max-w-317.5 flex-1 flex-col p-3">
          {error && <InfoMessage message={error} variant="error" />}
          <Routes>
            <Route path="/" element={<AlertList brandId={brand.id} />} />
            <Route
              path="/settings/:contactId?"
              element={<NotificationSettings key={brand.id} brandId={brand.id} />}
            />
            <Route
              path="/tracking-events"
              element={<TrackingEvents key={brand.id} brandId={brand.id} />}
            />
            <Route path="/jobs" element={<QueueStatus brandId={brand.id} />} />
            <Route path="/:id" element={<AlertDetail brandId={brand.id} />} />
            <Route path="*" element={<Navigate to="/" replace />} />
          </Routes>
        </main>
      </div>
    </div>
  );
}
