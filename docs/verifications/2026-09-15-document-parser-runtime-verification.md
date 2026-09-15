# 2026-09-15 문서 파서 런타임 검증

## 검증 범위

K-DATA 공개문서 수집·분석 파이프라인의 형식 분류, 전문 추출, 해시, 보호문서 분기, 내부·공개 산출물 분리 및 10일 주기를 검증했다. 이 검증에서는 원격 Supabase를 변경하지 않았다.

## 자동 계약 테스트

| 항목 | 결과 |
|---|---|
| HWPX ZIP/XML 전문 추출 | PASS |
| 선언 용어 내부 매칭 | PASS |
| 동일 입력의 결정적 projection SHA-256 | PASS |
| DRMONE/FASOO 탐지 후 비우회 중단 | PASS |
| 전문·문장 CSV의 internal 분리 | PASS |
| 공개 projection의 전문·절대경로 제외 | PASS |
| 월 경계를 넘는 정확한 10일 판정 | PASS |
| PDF/HWP magic byte 우선 판정 | PASS |
| HTML script/style 제외 전문 추출 | PASS |

실행 결과: 8개 테스트, 실패 0.

## 실제 보유 문서 표본

원본은 읽기 전용으로 처리하고 Git 제외 경로에 QA 산출물을 만들었다.

| 표본 | 탐지 형식 | 보호 상태 | 추출 상태 | 정규화 글자 수 | 추출 신뢰도 |
|---|---|---|---|---:|---:|
| 개인정보보호규칙 표본 | HWPX | clear | extracted | 35,766 | 100.000 |
| 정보공개청구 답변서 표본 | HWP/OLE | unknown | extracted | 4,845 | 97.000 |
| SLDA 문서대조 표본 | PDF | clear | extracted | 1,491 | 100.000 |

`HWP/OLE`의 보호 상태 `unknown`은 DRM 표식이 없다는 뜻이지 보호가 없음을 확정한다는 뜻은 아니다. HWP 내부 FileHeader의 암호화·배포용 플래그는 추출 단계에서 별도로 검사하며, 해당 표본은 전문 추출에 성공했다.

## 실제 공개 URL 수집 smoke test

K-DATA 현재 페이지 3개와 Wayback 조직도 2개를 allowlist를 통해 수집했다.

| 결과 | 값 |
|---|---:|
| 대상 | 5 |
| 성공 | 5 |
| 실패 | 0 |
| 원본 SHA-256 생성 | 5/5 |
| 정규화 전문 SHA-256 생성 | 5/5 |
| projection SHA-256 생성 | 5/5 |

테스트 산출물은 `work/` 아래에만 있으며 `.gitignore` 대상이다. 원문과 문장 단위 CSV는 저장소에 커밋하지 않았다.

## 판정

`RUNTIME_CONTRACT_MATCH_FOR_TESTED_SAMPLES`

현재 검증은 선택한 표본과 공개 URL에 대한 것이다. 모든 HWP 변형, 손상 PDF, 스캔 PDF, DRM 제품 버전을 포괄한다는 의미는 아니다. 스캔 PDF는 `needs_ocr`로 분기하며 OCR 자체는 아직 구현하지 않았다.

## 다음 단계

1. GitHub Actions 수동 실행으로 호스팅 환경에서 동일 결과 확인
2. 10일 주기 첫 예약 실행의 Artifact·해시 확인
3. DRM/손상/스캔 표본이 생길 때 회귀 테스트 추가
4. 원격 수집 테이블과 migration의 타입·제약을 read-only로 대조한 뒤 DB 적용 여부 결정
