import type { SidebarSection } from "@/components/Sidebar";

export const APP_NAVIGATE_EVENT = "pressay:navigate";

export const navigateToAppSection = (section: SidebarSection) => {
  window.dispatchEvent(
    new CustomEvent<SidebarSection>(APP_NAVIGATE_EVENT, { detail: section }),
  );
};
