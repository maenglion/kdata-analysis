"use client";

import { useMemo, useState } from "react";

type Status = "F" | "R" | "U" | "E";

const navItems = [
  ["overview", "분석 개요"],
  ["timeline", "시계열"],
  ["route", "처리 경로"],
  ["authority", "조직·권한"],
  ["matrix", "증거 매트릭스"],
  ["mismatch", "홈페이지 불일치"],
  ["requests", "청구·회신 현황"],
  ["history", "변경 이력"],
] as const;

const findings: Array<{
  id: string;
  status: Status;
  title: string;
  text: string;
  evidence: string;
}> = [
  {
    id: "F-01",
    status: "F",
    title: "동일 현업 결재선",
    text: "2026년 8월 개인정보 회신과 정보공개 결정이 데이터바우처 현업 결재선에서 처리됐다.",
    evidence: "EV-001 · EV-002",
  },
  {
    id: "F-02",
    status: "F",
    title: "인물 기준 연결·기술",
    text: "8월 3일 회신은 서로 다른 법인·사업자료와 법원 사실조회 사실을 한 사람을 기준으로 연결했다.",
    evidence: "EV-002 · EV-003",
  },
  {
    id: "R-01",
    status: "R",
    title: "현업부서 누적 위험",
    text: "동일 현업 결재선이 권리행사와 정보공개를 연속 처리해 목적이 다른 정보가 누적될 구조적 위험이 있다.",
    evidence: "F-01~F-07",
  },
  {
    id: "U-01",
    status: "U",
    title: "2026년 심사자료 접근",
    text: "현재 결재선 또는 법원문서 처리자가 2026년 신청·평가 자료를 실제 조회했는지는 확인되지 않았다.",
    evidence: "E-01~E-04 필요",
  },
  {
    id: "E-01",
    status: "E",
    title: "접속·전자결재·심사 메타데이터",
    text: "검색·열람·다운로드 로그, 전체 결재경로, 평가점수와 상태변경 이력이 다음 판정을 결정한다.",
    evidence: "P0 확보 대상",
  },
];

const timeline = [
  ["2019–2022", "복덕판㈜ 사업자료", "과거 사업자료", "담당자·보유위치·접근권한"],
  ["2023–2024", "시뮬라크르에이트 사업자료", "과거 사업자료", "담당자·보유위치·접근권한"],
  ["2025.12.23", "법원 사실조회 촉탁 수령", "법원문서", "최초 접수·배부·공람 경로"],
  ["2026.01.09", "K-DATA 사실조회 회신", "법원문서", "작성·검토·결재·발송자"],
  ["2026.03", "수요기업 신청", "사업심사", "자동검증·심사자 배정"],
  ["2026.04", "수요기업 탈락", "사업심사", "점수·사유코드·상태변경"],
  ["2026.08.03", "개인정보 회신 · 활용26-2808", "개인정보 처리", "연결·기술 확인"],
  ["2026.08.04", "활용26-2808 수령·저장", "수령 메타데이터", "별도 발신 문서 아님"],
  ["2026.08.07", "정보 부분공개 결정 · 활용26-2877", "정보공개", "후속 공개범위 판단"],
  ["향후", "수요·공급기업 신청·평가", "미래 사업심사", "분리·차단과 접근로그"],
];

const evidenceRows = [
  ["EV-001", "2026.08.07 정보 부분공개 결정통지", "A", "100,272 B", "f8ef…dae8"],
  ["EV-002", "정보공개·열람 담당자 및 조직도 대조", "B", "393,078 B", "bd2b…3c26"],
  ["EV-003", "사업부 결재선 개인정보 결합·업무경계 조사", "B", "15,238 B", "5b75…057e"],
  ["EV-004", "법무·감사·정보보호 협조여부 청구 초안", "B", "7,971 B", "633c…b248"],
  ["WEB-001", "조직도·담당업무 정규화 스냅샷", "A", "1,371 B", "c4be…701e"],
  ["WEB-002", "정보공개 업무처리절차 스냅샷", "A", "1,247 B", "a2bb…f7e9"],
  ["WEB-003", "임직원 행동강령 스냅샷", "A", "1,330 B", "a24e…30af"],
  ["WEB-004", "개인정보처리방침 스냅샷", "A", "1,249 B", "340d…fb1f"],
];

const requestRows = [
  ["E-01", "시스템 검색·열람·다운로드 로그", "P0", "회신 대기"],
  ["E-02", "권한그룹·부여·변경·말소 기록", "P0", "회신 대기"],
  ["E-03", "자격·요건 검토와 자동검증 결과", "P0", "청구 보강"],
  ["E-04", "평가표·점수·의견·위원 배정", "P0", "청구 보강"],
  ["E-05", "심사위원 제공자료·주의정보", "P0", "청구 보강"],
  ["E-06", "상태변경·자동 제외·자격배제 이력", "P0", "청구 보강"],
  ["E-07", "법원문서 접수부터 발송까지 전체 이력", "P0", "회신 대기"],
  ["E-08", "활용26-2808·2877 전자결재 전체", "P0", "회신 대기"],
  ["E-09", "첨부파일 목록·열람·재사용 기록", "P0", "회신 대기"],
  ["E-10", "정보보호·개인정보책임자·감사실 협조", "P0", "회신 대기"],
  ["E-11", "접수·분류·이송·재배부 기록", "P0", "회신 대기"],
  ["E-12", "홈페이지 수정·승인·변경 이력", "P1", "추가 청구"],
];

function StatusBadge({ status }: { status: Status }) {
  const labels = { F: "확정", R: "위험", U: "미확정", E: "필요 증거" };
  return <span className={`status status-${status.toLowerCase()}`}>{labels[status]}</span>;
}

function SectionTitle({ eyebrow, title, note }: { eyebrow: string; title: string; note: string }) {
  return (
    <div className="section-title">
      <div>
        <p className="eyebrow">{eyebrow}</p>
        <h2>{title}</h2>
      </div>
      <p className="section-note">{note}</p>
    </div>
  );
}

export default function Home() {
  const [filter, setFilter] = useState<"ALL" | Status>("ALL");
  const visibleFindings = useMemo(
    () => findings.filter((finding) => filter === "ALL" || finding.status === filter),
    [filter],
  );

  const goTo = (id: string) => {
    document.getElementById(id)?.scrollIntoView({ behavior: "smooth", block: "start" });
  };

  return (
    <main>
      <header className="topbar">
        <button className="brand" onClick={() => goTo("overview")} aria-label="분석 개요로 이동">
          <span className="brand-mark">K</span>
          <span>
            <b>K-DATA Evidence Ledger</b>
            <small>재현 가능한 처리경로 분석</small>
          </span>
        </button>
        <div className="topbar-meta">
          <span className="private-dot" />
          비공개 검토본
          <span className="version">v1.0 · 2026-08-13</span>
        </div>
      </header>

      <div className="shell">
        <aside className="sidebar" aria-label="분석 메뉴">
          <p className="sidebar-label">ANALYSIS INDEX</p>
          <nav>
            {navItems.map(([id, label], index) => (
              <button key={id} onClick={() => goTo(id)}>
                <span>{String(index + 1).padStart(2, "0")}</span>
                {label}
              </button>
            ))}
          </nav>
          <div className="sidebar-card">
            <span>판정 원칙</span>
            <b>사실과 추론을 분리</b>
            <p>새 증거는 기존 판정을 덮어쓰지 않고 변경 이력으로 남깁니다.</p>
          </div>
        </aside>

        <div className="content">
          <section id="overview" className="hero section-anchor">
            <div className="hero-copy">
              <p className="eyebrow">REPRODUCIBLE DATA-LINEAGE AUDIT</p>
              <h1>개인정보 처리와 결재경로를<br />증거 데이터셋으로 재구성하다</h1>
              <p className="hero-lead">
                8월 3일 회신의 인물 기준 연결·기술과 8월 7일 공개범위 판단을 분리하고,
                확정 사실·구조적 위험·미확정 쟁점·필요 증거를 독립된 코드로 관리합니다.
              </p>
              <div className="hero-actions">
                <button className="primary" onClick={() => goTo("matrix")}>증거 매트릭스 보기</button>
                <button className="secondary" onClick={() => goTo("requests")}>P0 기록 확인</button>
              </div>
            </div>
            <div className="hero-ledger" aria-label="판정 현황">
              <div className="ledger-head">
                <span>판정 스냅샷</span>
                <code>MASTER / v1.0</code>
              </div>
              <div className="score-grid">
                <div><b>08</b><span>확정 사실</span></div>
                <div><b>02</b><span>구조적 위험</span></div>
                <div><b>05</b><span>미확정</span></div>
                <div><b>12</b><span>필요 증거</span></div>
              </div>
              <div className="checksum">
                <span>증거 원본</span><b>4</b>
                <span>웹 스냅샷</span><b>4</b>
                <span>해시 기록</span><b>8 / 8</b>
              </div>
            </div>
          </section>

          <section className="principle-strip" aria-label="핵심 판독 원칙">
            <div><StatusBadge status="F" /><p>실제 연결·기술</p></div>
            <span className="arrow">→</span>
            <div><StatusBadge status="R" /><p>현업 누적 위험</p></div>
            <span className="arrow">→</span>
            <div><StatusBadge status="U" /><p>심사상 실제 이용</p></div>
            <span className="arrow">→</span>
            <div><StatusBadge status="E" /><p>로그로 판정</p></div>
          </section>

          <section className="panel findings-panel">
            <SectionTitle eyebrow="JUDGMENT REGISTRY" title="핵심 판정" note="고발 문장이 아니라 검증 가능한 명제로 기록합니다." />
            <div className="filter-row" role="group" aria-label="판정 필터">
              {(["ALL", "F", "R", "U", "E"] as const).map((item) => (
                <button key={item} className={filter === item ? "active" : ""} onClick={() => setFilter(item)}>
                  {item === "ALL" ? "전체" : item}
                </button>
              ))}
            </div>
            <div className="finding-grid">
              {visibleFindings.map((finding) => (
                <article className="finding-card" key={finding.id}>
                  <div className="finding-id"><code>{finding.id}</code><StatusBadge status={finding.status} /></div>
                  <h3>{finding.title}</h3>
                  <p>{finding.text}</p>
                  <footer>{finding.evidence}</footer>
                </article>
              ))}
            </div>
          </section>

          <section id="timeline" className="panel section-anchor">
            <SectionTitle eyebrow="NORMALIZED TIMELINE" title="시계열" note="사건일, 문서 기능, 검증 대상을 한 축에 정렬합니다." />
            <div className="timeline">
              {timeline.map(([date, event, layer, verify], index) => (
                <article key={`${date}-${event}`} className={date === "2026.08.04" ? "muted-event" : ""}>
                  <div className="timeline-marker"><span>{index + 1}</span></div>
                  <time>{date}</time>
                  <div><h3>{event}</h3><p>{layer}</p></div>
                  <aside>{verify}</aside>
                </article>
              ))}
            </div>
            <div className="callout warning">
              <b>인과관계 잠금</b>
              <p>2026년 4월 탈락은 확정 사실이지만, 법원 사실조회나 결합정보가 원인이라고 단정하지 않습니다. 평가점수·자동검증·접속로그·상태변경 이력으로만 갱신합니다.</p>
            </div>
          </section>

          <section id="route" className="panel section-anchor">
            <SectionTitle eyebrow="PROCESS TRACE" title="처리 경로" note="문서 기능은 연결하되 동일 시스템 저장은 미확정으로 남깁니다." />
            <div className="route-map">
              {[
                ["01", "법원 사실조회 촉탁", "E-07", "접수·배부·공람"],
                ["02", "과거 사업자료 조회", "F-02", "인물 기준 연결·기술"],
                ["03", "개인정보 권리행사", "F-01", "현업 결재선"],
                ["04", "정보공개 결정", "F-03", "후속 공개범위 판단"],
                ["05", "향후 사업심사", "R-02", "분리·차단 필요"],
              ].map(([num, title, code, text], index) => (
                <div className="route-step" key={num}>
                  <span className="route-num">{num}</span>
                  <div><h3>{title}</h3><code>{code}</code><p>{text}</p></div>
                  {index < 4 && <span className="route-line" aria-hidden="true" />}
                </div>
              ))}
            </div>
            <div className="callout">
              <b>경로의 의미</b>
              <p>단계 간 시간적·조직적 연결을 표시합니다. 각 자료가 동일 데이터베이스 또는 문서철에 저장됐다는 뜻은 아니며, E-01·E-02·E-09로 검증합니다.</p>
            </div>
          </section>

          <section id="authority" className="panel section-anchor">
            <SectionTitle eyebrow="ORGANIZATION & AUTHORITY" title="조직·권한" note="공개 업무분장과 실제 내부 권한을 별도로 검증합니다." />
            <div className="org-grid">
              <article><span>사업 현업</span><h3>데이터바우처팀</h3><p>모집 · 선정평가 · 협약 · 이행점검 · 결과평가 · 제재 · 민원 · 시스템 관리</p><code>WEB-001</code></article>
              <article><span>개인정보 통제</span><h3>정보보호인프라팀</h3><p>개인정보보호 · 권리행사 접수·처리 · 내부 업무시스템 운영지원</p><code>WEB-001 · 004</code></article>
              <article><span>법률·감사</span><h3>감사실</h3><p>법률자문 · 소송관리 · 신고사건 조사 · 감사 · 청렴업무</p><code>WEB-001 · 003</code></article>
              <article><span>검증 대상</span><h3>실제 전결·배부 규칙</h3><p>직제규정 · 업무분장표 · 위임전결규정 · 행동강령책임관 지정문서</p><code>E-07 · 08 · 10 · 11</code></article>
            </div>
          </section>

          <section id="matrix" className="panel section-anchor">
            <SectionTitle eyebrow="EVIDENCE MATRIX" title="증거 매트릭스" note="원문은 비공개 보관하고 증거번호·등급·해시만 공개층에 둡니다." />
            <div className="table-wrap">
              <table>
                <thead><tr><th>증거 ID</th><th>문서</th><th>등급</th><th>크기</th><th>SHA-256</th></tr></thead>
                <tbody>
                  {evidenceRows.map((row) => (
                    <tr key={row[0]}>{row.map((cell, idx) => <td key={cell}>{idx === 0 || idx === 4 ? <code>{cell}</code> : cell}</td>)}</tr>
                  ))}
                </tbody>
              </table>
            </div>
            <p className="micro-note">SHA-256은 원본 또는 정규화 스냅샷의 무결성 값입니다. 웹 해시는 원시 HTML이 아닌 정규화 스냅샷을 대상으로 합니다.</p>
          </section>

          <section id="mismatch" className="panel section-anchor">
            <SectionTitle eyebrow="OFFICIAL-PAGE DIFF" title="홈페이지 불일치" note="문언 불일치와 실제 오배부를 구분합니다." />
            <div className="diff-grid">
              <article><code>W-01</code><h3>현재 조직도</h3><p>정보보호인프라팀·데이터바우처팀·감사실의 공개 업무가 기능별로 구분됩니다.</p><footer>기준점 · WEB-001</footer></article>
              <article><code>W-02</code><h3>부서명 병존</h3><p>정보공개 절차 페이지에 경영지원팀과 경영기획본부 문언이 함께 남아 있습니다.</p><footer>현행화 불일치 · WEB-002</footer></article>
              <article><code>W-03</code><h3>표 제목 불일치</h3><p>정보공개 담당표 자리에 공공데이터제공 책임관·실무자라는 제목이 표시됩니다.</p><footer>편집·관리 문제 · WEB-002</footer></article>
              <article><code>W-04</code><h3>정보보호팀 명칭</h3><p>개인정보처리방침 상단과 본문에서 정보보호팀·정보보호인프라팀 명칭이 병존합니다.</p><footer>현행화 불일치 · WEB-004</footer></article>
            </div>
            <div className="hash-strip"><span>수집시각</span><b>2026-08-13 22:46 KST</b><span>스냅샷</span><b>4 / 4 해시 기록</b><span>다음 검증</span><b>E-12 변경이력</b></div>
          </section>

          <section id="requests" className="panel section-anchor">
            <SectionTitle eyebrow="REQUEST / RESPONSE TRACKER" title="청구·회신 현황" note="답변이 들어오면 각 행을 확정·기각·계속 미확정으로 갱신합니다." />
            <div className="request-summary">
              <div><span>P0</span><b>11</b><small>최우선 기록</small></div>
              <div><span>P1</span><b>1</b><small>홈페이지 현행화</small></div>
              <div><span>응답</span><b>0</b><small>신규 회신 대기</small></div>
              <div><span>완료</span><b>0%</b><small>판정 갱신 전</small></div>
            </div>
            <div className="table-wrap">
              <table>
                <thead><tr><th>ID</th><th>요구 기록</th><th>우선순위</th><th>상태</th></tr></thead>
                <tbody>
                  {requestRows.map((row) => (
                    <tr key={row[0]}><td><code>{row[0]}</code></td><td>{row[1]}</td><td><span className={`priority ${row[2].toLowerCase()}`}>{row[2]}</span></td><td>{row[3]}</td></tr>
                  ))}
                </tbody>
              </table>
            </div>
          </section>

          <section id="history" className="panel section-anchor">
            <SectionTitle eyebrow="CHANGE LOG" title="변경 이력" note="판정 변경의 이유와 근거를 보존합니다." />
            <div className="history-row">
              <div><code>v1.0</code><time>2026-08-13</time></div>
              <div><h3>기준 판본 생성</h3><p>중복·구판 문장을 제거하고, 8월 4일을 별도 발신 문서가 아닌 활용26-2808의 수령·저장 시점으로 정정했습니다. 증거번호·해시·판정코드를 도입하고 공개층의 개인정보를 제거했습니다.</p></div>
              <span>판정 체계 생성</span>
            </div>
            <div className="update-protocol">
              <h3>다음 회신이 도착하면</h3>
              <ol>
                <li>원본 보존 후 SHA-256·크기·수령시각 기록</li>
                <li>회신 항목을 E-01~E-12에 연결</li>
                <li>U 판정을 확정·기각·계속 미확정으로 갱신</li>
                <li>공개 전 개인식별정보와 절대경로 재검사</li>
              </ol>
            </div>
          </section>

          <footer className="site-footer">
            <div><span className="brand-mark">K</span><b>K-DATA Evidence Ledger</b></div>
            <p>이 사이트는 비공개 분석 시연판입니다. 원본 증거와 개인식별정보를 포함하지 않습니다.</p>
            <code>MASTER v1.0 · 2026-08-13 KST</code>
          </footer>
        </div>
      </div>
    </main>
  );
}

