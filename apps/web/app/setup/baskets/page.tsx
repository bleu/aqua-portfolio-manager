import { CreateBasketsPage } from "@/components/pages/CreateBasketsPage";
import { initialBaskets, safeTokens } from "@/lib/mockBaskets";

export default function Page() {
  return (
    <CreateBasketsPage
      network="Ethereum"
      safeAddress="0x71A4D045E3dD40321B5a35E03eD9fC5A8e9F2C3B"
      baskets={initialBaskets}
      safeTokens={safeTokens}
    />
  );
}
