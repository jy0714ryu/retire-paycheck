"""은퇴월급 스토어 스크린샷 5장 — 아이보리·남색·골드 틀 + 한 줄 설명 (v2.2).

사용 (app 폴더에서):
  flutter test tool/screenshot_test.dart --update-goldens --dart-define=SHOT_H=1920
  python3 tool/make_store_frames.py tool/goldens/store <출력 폴더>
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

SHOTS = Path(sys.argv[1]); OUT = Path(sys.argv[2]); OUT.mkdir(parents=True, exist_ok=True)
FONTS = Path(__file__).resolve().parent.parent / "assets/fonts"
IVORY = (246, 243, 236); NAVY = (15, 30, 51); GOLD = (168, 133, 79); GRAY = (107, 99, 88)
serif = lambda s: ImageFont.truetype(str(FONTS / "NotoSerifKR-Bold.ttf"), s)
sans = lambda s: ImageFont.truetype(str(FONTS / "IBMPlexSansKR-Medium.ttf"), s)

PAGES = [
    ("2_plan", "어느 계좌부터 꺼낼까", "인출 순서별 총 세금을 비교해요", "연금저축·IRP·ISA · 20~30년 계산"),
    ("3b_health", "은퇴 후 건보료,", "미리 계산해 두세요", "피부양자 유지 · 지역 보험료 · 퇴직 후 36개월 비교"),
    ("1_this_month", "배당과 연금을", "한 달력에", "계좌 안 배당까지 [배당 전체]로 한눈에"),
    ("2b_plan_yearly", "해마다 얼마 꺼내고", "세금은 얼마일까", "연도별 인출 · 세금 · 국민연금 표"),
    ("0_quick_start", "세 칸이면 시작", "로그인·계좌 연동 없이", "입력한 자산 정보는 폰에만 저장돼요"),
]
W, H = 1080, 1920
for i, (name, l1, l2, sub) in enumerate(PAGES, 1):
    cv = Image.new("RGBA", (W, H), IVORY + (255,)); d = ImageDraw.Draw(cv)
    d.rectangle((84, 112, 84 + 56, 116), fill=GOLD)
    d.text((80, 140), l1, font=serif(68), fill=NAVY)
    d.text((80, 230), l2, font=serif(68), fill=NAVY)
    d.text((82, 342), sub, font=sans(32), fill=GRAY)
    shot = Image.open(SHOTS / f"{name}.png").convert("RGB")
    sw = 860; sh = round(shot.height * sw / shot.width)
    shot = shot.resize((sw, sh), Image.LANCZOS)
    x, y, r = (W - sw) // 2, 450, 40
    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle((x, y + 16, x + sw, y + sh + 16), r, fill=(40, 30, 15, 70))
    cv = Image.alpha_composite(cv, shadow.filter(ImageFilter.GaussianBlur(24)))
    frame = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(frame).rounded_rectangle((x - 12, y - 12, x + sw + 12, y + sh + 12), r + 10, fill=NAVY + (255,))
    cv = Image.alpha_composite(cv, frame)
    m = Image.new("L", (sw, sh), 0); ImageDraw.Draw(m).rounded_rectangle((0, 0, sw - 1, sh - 1), r, fill=255)
    cv.paste(shot, (x, y), m)
    cv.convert("RGB").save(OUT / f"{i:02d}_{name}.png")
print("ok")
