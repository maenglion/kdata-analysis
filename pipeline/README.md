# 공공기관 문서 수집·분석 파이프라인

이 파이프라인은 K-DATA의 공개 문서를 2년간 반복 수집하고, 같은 실행규약을 다른 기관의 **별도 저장소·별도 DB**에서도 재사용하기 위한 결정적 파서다. 이 저장소에서는 `kdata.public.json`만 활성 운영한다. `kodit.example.json`은 코드 재사용 예시이며 K-DATA 작업에서 실행하지 않는다.

## 처리 체인

`원본 바이트 → SHA-256 → 형식·보호 분류 → 전문 추출 → NFC 정규화 → 문장 단위 분할 → 내부 매칭 → 추출 신뢰도 → 결정적 공개 투영`

- HWPX: ZIP 구조와 `Contents/section*.xml`을 검사해 전문을 추출한다.
- HWP: OLE `FileHeader`와 `BodyText/Section*` 레코드를 읽는다.
- PDF: 텍스트 계층을 추출하며 텍스트가 없으면 `needs_ocr`로 보낸다.
- DRMONE/FASOO: 표식이 확인되면 `protected`로 분류하고 추출을 중단한다. 우회·해제·암호 추측은 하지 않는다.
- 해시: 원본, 정규화 전문, 공개 투영에 각각 SHA-256을 기록한다.
- 신뢰도: 파서가 전문을 얼마나 충실하게 뽑았는지를 나타내는 `extraction_confidence`다. 문서 내용의 진실성이나 K-DATA 주장 판정 점수가 아니다.

## 공개와 내부 출력의 경계

각 문서는 다음처럼 분리된다.

```text
<output>/<institution>/<source>/
├─ raw/source.*                 # 내부: 원본
├─ internal/runtime-manifest.json
├─ internal/normalized-text.txt
├─ internal/parsed-units.csv
└─ publish/publish-document.json # 공개 가능 메타데이터만
```

전문과 문장 단위 CSV는 개인정보가 들어갈 수 있으므로 공개 저장소나 공개 Supabase 스키마에 자동 게시하지 않는다. `publish-document.json`에도 전문·로컬 절대경로·인증정보를 넣지 않는다.

## 실행

```powershell
python -m pip install -r pipeline/requirements.txt
$env:PYTHONPATH = "pipeline/src"
python -m unittest discover -s pipeline/tests -v
python -m evidence_ingest.cli inspect <파일> --institution kdata --source-id LOCAL-001 --out work/local-001
python -m evidence_ingest.cli collect --profile pipeline/profiles/kdata.public.json --out work/collection
```

10일 간격 판정은 달력의 매월 1·11·21일이 아니라 기준일로부터 경과일을 나눈 나머지로 계산한다. GitHub Actions는 매일 한 번 깨어나지만 2026-09-15부터 2028-09-15까지 정확히 10일 배수인 날에만 수집한다. 수동 실행은 주기와 무관하게 가능하다. 원문 없는 공개 해시 인덱스는 `snapshots/kdata/YYYY-MM-DD/collection-index.json`으로 Git 이력에 남고, 원문·전문은 90일 Artifact에만 임시 보관한다.

## DB 적재 계약

현재 파서는 파일 산출물까지만 만든다. Supabase 반영은 별도의 승인된 적재 작업에서 다음 순서를 지킨다.

1. 원본 메타데이터와 해시를 `evidence`·`ingest_batches`에 기록한다.
2. 전문은 비공개 경계 안에서 `parsed_claim_units`로 적재한다.
3. 공개 투영은 승인·비식별 검사를 통과한 필드만 `publish` View로 노출한다.
4. 주장 판정은 별도 루브릭 기반 `evaluation_run`으로 생성한다. 추출 신뢰도를 사실지지 점수로 대체하지 않는다.
5. 각 실행은 parser/runtime/methodology 버전을 고정하고 기존 행을 덮어쓰지 않는다.
