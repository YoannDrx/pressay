import type { SidebarSection } from "@/components/Sidebar";

interface PageAtmosphereProps {
  section: SidebarSection;
}

export function PageAtmosphere({ section }: PageAtmosphereProps) {
  return (
    <div className="page-atmosphere" data-section={section} aria-hidden="true">
      <span className="page-atmosphere-orbit page-atmosphere-orbit-outer" />
      <span className="page-atmosphere-orbit page-atmosphere-orbit-inner" />
      <span className="page-atmosphere-signal" />
    </div>
  );
}
