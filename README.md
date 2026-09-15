# K-DATA Evidence Ledger

K-DATA의 개인정보 처리, 결재경로, 사업심사 및 정보공개 처리 과정을 재현 가능한 증거 데이터셋으로 구조화하는 프로젝트다. 사실과 추론을 분리하고, 루브릭 입력·게이트·6단계 판정·사유·변경 이력을 연결한다.

- 배포: <https://kdata-evidence-ledger.netlify.app/>
- 기관 분류: 한국데이터산업진흥원(K-DATA)
- KODIT와 저장소·DB·배포·환경변수·원자료를 공유하지 않는다.

## 판정 원칙

최종 상태는 `confirmed`, `supported`, `conditional`, `insufficient`, `contradicted`, `unassessed`의 6단계다. 점수는 분석축이며 상태를 직접 결정하지 않는다. 상태는 버전이 고정된 방법론의 게이트 결과로 산출하고, 실패 게이트·부족증거·결정 게이트를 함께 저장한다. 기존 판정은 덮어쓰지 않고 새 evaluation run으로 이력을 남긴다.

## 구성

- `app/`: React 19·Vinext 화면
- `pipeline/`: HWP·HWPX·PDF 수집·전문 추출·DRM 분류·SHA-256·결정적 투영
- `supabase/migrations/`: K-DATA 전용 원장·루브릭·게이트·수집 투영 스키마
- `supabase/tests/`: DB 판정 엔진 계약 테스트
- `docs/decisions/`: 중요한 설계·운영 결정
- `docs/verifications/`: 실행·원격 상태 검증 기록

파서 실행법과 공개/내부 출력 경계는 [pipeline/README.md](./pipeline/README.md)를 따른다.

## 로컬 실행

요구사항: Node.js 22.13.0 이상, npm, Python 3.11 이상.

```powershell
npm install
npm run dev

python -m pip install -r pipeline/requirements.txt
$env:PYTHONPATH = "pipeline/src"
python -m unittest discover -s pipeline/tests -v
```

Netlify 빌드는 `npm run build:netlify`이며 `netlify.toml`과 Nitro Netlify preset을 사용한다. 수동 publish directory를 지정하지 않는다.

## 데이터·보안 경계

- 원본 사건자료, 전문, 개인정보, 로컬 절대경로, 인증정보를 공개 저장소에 넣지 않는다.
- 공개 화면에는 승인된 증거번호·등급·축약/공개 해시·판정 결과만 표시한다.
- 수집 파이프라인의 `raw`와 `internal` 산출물은 Git에서 제외한다.
- DRMONE/FASOO 문서는 식별만 하고 우회하지 않는다.
- Supabase의 RLS 활성화와 실제 policy/grant는 별도 검증한다. publish View가 존재해도 명시적 승인 전에는 브라우저 접근을 열지 않는다.

## 현재 작업 순서

1. 수집·파서 runtime contract 검산
2. 원격 Supabase drift를 읽기 전용으로 대조
3. RLS policy·역할별 접근 계약 확정
4. 원자료와 claim unit 비공개 적재
5. 루브릭 기반 evaluation run 생성·검산
6. 인간 승인된 최신 run으로 화면 상수 교체

중요한 변경은 코드만 고치지 않고 [의사결정 기록](./docs/decisions/README.md)과 검증 기록에 함께 남긴다.
