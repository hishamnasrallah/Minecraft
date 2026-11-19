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
- `main.py` — اللعبة نفسها: العرض، اللاعب، الواجهة، كسر ووضع البلوكات.
- `tests/` — اختبارات `world.py` (`pip install -r requirements-dev.txt && pytest`).

العالم مقسوم لـ chunks حجمها 16×16، وكل chunk إلها mesh واحدة فيها بس الوجوه الظاهرة. هاد اللي بخلي الأداء مقبول ببايثون.
الحفظ بخزّن الـ seed وتعديلات اللاعب بس، مش كل البلوكات.

## أفكار للخطوات الجاية / Next steps

- عالم لا نهائي (توليد chunks حوالين اللاعب وإزالة البعيدة)
- textures بدل الألوان
- مي وكهوف
- inventory و crafting
- multiplayer بسيرفر Python (WebSockets)
