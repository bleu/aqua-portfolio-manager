import { FirstAccessIntroductionPage } from "@/components/pages/FirstAccessIntroductionPage";
import { currentAllocation, targetAllocation } from "@/lib/mockData";

export default function Page() {
  return <FirstAccessIntroductionPage currentAllocation={currentAllocation} targetAllocation={targetAllocation} />;
}
