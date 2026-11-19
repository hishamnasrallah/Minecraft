# BlockWorld

لعبة sandbox ثلاثية الأبعاد بالبلوكات، مكتوبة بـ Python باستخدام [Ursina](https://www.ursinaengine.org/). بتشتغل محلياً على جهازك.

A small 3D voxel sandbox written in Python with the Ursina engine. Runs locally.

## التشغيل / Run

```bash
python -m venv .venv
source .venv/bin/activate        # Windows: .venv\Scripts\activate
pip install -r requirements.txt
python main.py                   # يكمل من آخر حفظ
python main.py --new             # عالم جديد
```

## التحكم / Controls

| المفتاح | الوظيفة |
|---|---|
| WASD + الماوس | حركة ونظر |
| Space | قفز |
| كليك يسار | كسر بلوك |
| كليك يمين | وضع بلوك |
| 1-8 أو عجلة الماوس | اختيار البلوك |
| F5 | حفظ |
| Esc | حفظ وخروج |

## البنية / Structure

- `world.py` — بيانات العالم، توليد التضاريس (noise)، بناء الـ mesh لكل chunk، الحفظ والتحميل. بدون أي اعتماد على Ursina عشان يتجرّب بسهولة.
- `textures.py` — بيرسم textures البلوكات (pixel art) بالكود وبجمعها بصورة وحدة (atlas).
- `main.py` — اللعبة نفسها: العرض، اللاعب، الواجهة، كسر ووضع البلوكات.
- `tests/` — اختبارات `world.py` (`pip install -r requirements-dev.txt && pytest`).

العالم **لا نهائي**: مقسوم لـ chunks حجمها 16×16 بتتولد من الـ seed لما تقرّب منها، والبعيدة بتنشال من الذاكرة.
كل chunk إلها mesh واحدة فيها بس الوجوه الظاهرة، وبتنبنى 2 chunks بكل frame عشان ما يصير تقطيع.
الحفظ بخزّن الـ seed وتعديلات اللاعب بس، فالتعديلات بترجع لما ترجع لنفس المكان.

إعدادات بأول `main.py`: `RENDER_DISTANCE` (كم chunk حواليك بتنرسم) و `CHUNKS_PER_FRAME`.

## Textures

الـ textures بتنرسم تلقائياً. إذا بدك ترسم تبعتك:

```bash
python textures.py      # بيطلع textures/atlas.png
```

عدّل الصورة بأي برنامج رسم (حافظ على شبكة 4×4 وترتيب `TILES` بـ `world.py`)، واللعبة رح تستخدم نسختك تلقائياً.

## أفكار للخطوات الجاية / Next steps

- مي وكهوف
- inventory و crafting
- multiplayer بسيرفر Python (WebSockets)
