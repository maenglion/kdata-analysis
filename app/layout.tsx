import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "K-DATA Evidence Ledger",
  description: "K-DATA 개인정보 처리와 결재경로를 재현 가능한 증거 데이터셋으로 분석한 비공개 시연판",
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="ko">
      <body>{children}</body>
    </html>
  );
}

