class_name AnimalView
extends Node3D
## Blocky models for the creatures (port of animal_models.py). Every part is a box with
## terrain-like face shading. For speed the still parts of a species (per colour variant) are
## merged into ONE shared mesh, and only legs / wings / tails are separate (shared) meshes, so
## an animal is 1-5 draw calls. Brightness comes from a small set of shared materials
## (quantised light levels), so nothing is allocated per frame. Far animals are hidden.

const FUR := Color8(143, 117, 92)
const CREAM := Color8(224, 212, 189)
const DARK := Color8(31, 26, 23)
const TAN := Color8(161, 115, 71)
const BELLY := Color8(219, 194, 153)
const HOOF := Color8(64, 46, 31)
const FEATHER := Color8(153, 135, 107)
const GREEN := Color8(33, 115, 56)
const ORANGE := Color8(242, 153, 38)
const WING := Color8(115, 102, 82)
const SHADOW := Color8(38, 30, 56)
const SHADOW_EDGE := Color8(62, 48, 92)
const GLOW := Color8(150, 255, 225)
const FACE := Color8(226, 208, 184)
const HORN := Color8(196, 164, 112)
const SOOT := Color8(58, 50, 48)
const SOOT_LIGHT := Color8(92, 80, 74)
const NOSE := Color8(160, 96, 96)
const HEN := Color8(190, 118, 62)
const HEN_DARK := Color8(112, 64, 34)
const COMB := Color8(204, 44, 44)
const GOAT := Color8(206, 200, 188)
const GOAT_DARK := Color8(120, 110, 98)
const AMBER := Color8(214, 168, 46)
const FROG := Color8(84, 152, 62)
const FROG_BELLY := Color8(206, 214, 146)
const SHELL := Color8(92, 112, 58)
const SHELL_DARK := Color8(66, 84, 42)
const SHELL_RIM := Color8(160, 146, 92)
const TURTLE_SKIN := Color8(128, 156, 96)
const LIZARD := Color8(204, 166, 96)
const LIZARD_DARK := Color8(150, 112, 60)
const DEWLAP := Color8(64, 126, 210)
const FIN := Color8(255, 255, 255)
const BEAK := Color8(236, 176, 52)
const FIREGLOW := Color8(214, 255, 110)
const WING_PALE := Color8(220, 225, 230)
const BRAMBLE := Color8(64, 82, 40)
const BRAMBLE_DARK := Color8(44, 58, 28)
const THORN := Color8(214, 200, 150)
const EMBER := Color8(255, 86, 60)
const GLOB := Color8(92, 142, 70)
const GLOB_TOP := Color8(130, 176, 84)
const EYE_WHITE := Color8(236, 232, 214)
const PUPIL := Color8(255, 216, 60)
# placeholders replaced by the animal's colour variant (VAR) and a darker shade of it (VAR2)
const VAR := Color(1, 0, 1)
const VAR2 := Color(0.5, 0, 0.5)
const PALETTES := {
	"rabbit": [Color8(143, 117, 92), Color8(236, 236, 240)],
	"fish": [Color8(240, 138, 40), Color8(184, 198, 208), Color8(70, 122, 204)],
	"bird": [Color8(66, 116, 204), Color8(204, 66, 52), Color8(134, 102, 70)],
	"butterfly": [Color8(250, 210, 50), Color8(246, 132, 36), Color8(80, 150, 250), Color8(244, 244, 236)],
	"horse": [Color8(122, 80, 48), Color8(60, 46, 38), Color8(224, 214, 196), Color8(160, 96, 52)],
	"worker": [Color8(86, 150, 64), Color8(128, 132, 142), Color8(238, 234, 222)],   # farmer, smith, baker
}
const SKIN := Color8(214, 170, 132)
const SKIN_DARK := Color8(180, 130, 98)
const PANTS := Color8(62, 76, 120)
const BOOT := Color8(70, 50, 36)
const HAIR := Color8(92, 64, 40)
const SCALES := {"globlet": 0.5}      # species drawn as a smaller copy of another
const SAME_AS := {"globlet": "glob"}

# [name, position, size, colour]; positions are relative to the feet (centre for flyers), facing +z.
# "leg" parts hang down from the given hip and swing; "wing" parts are hinged at their inner
# edge and flap; "tail" parts are hinged at their front and wag; "glow" parts ignore darkness.
const MODELS := {
	"rabbit": [
		["body", Vector3(0, .22, 0), Vector3(.32, .28, .46), VAR], ["head", Vector3(0, .4, .24), Vector3(.24, .22, .22), VAR],
		["ear", Vector3(.06, .6, .21), Vector3(.06, .22, .04), VAR], ["ear", Vector3(-.06, .6, .21), Vector3(.06, .22, .04), VAR],
		["eye", Vector3(.121, .43, .29), Vector3(.02, .05, .05), DARK], ["eye", Vector3(-.121, .43, .29), Vector3(.02, .05, .05), DARK],
		["tail", Vector3(0, .27, -.26), Vector3(.12, .12, .08), CREAM],
		["paw", Vector3(.09, .05, .15), Vector3(.08, .1, .1), VAR], ["paw", Vector3(-.09, .05, .15), Vector3(.08, .1, .1), VAR],
		["paw", Vector3(.12, .06, -.15), Vector3(.1, .12, .16), VAR], ["paw", Vector3(-.12, .06, -.15), Vector3(.1, .12, .16), VAR],
	],
	"deer": [
		["body", Vector3(0, .88, 0), Vector3(.45, .42, .95), TAN], ["belly", Vector3(0, .68, 0), Vector3(.4, .04, .8), BELLY],
		["neck", Vector3(0, 1.14, .42), Vector3(.2, .42, .2), TAN], ["head", Vector3(0, 1.36, .55), Vector3(.24, .24, .34), TAN],
		["nose", Vector3(0, 1.32, .735), Vector3(.12, .1, .04), HOOF],
		["ear", Vector3(.15, 1.48, .5), Vector3(.12, .07, .04), TAN], ["ear", Vector3(-.15, 1.48, .5), Vector3(.12, .07, .04), TAN],
		["eye", Vector3(.121, 1.4, .62), Vector3(.02, .05, .05), DARK], ["eye", Vector3(-.121, 1.4, .62), Vector3(.02, .05, .05), DARK],
		["patch", Vector3(0, .98, -.5), Vector3(.1, .14, .06), BELLY],
		["leg", Vector3(.15, .67, .36), Vector3(.11, .67, .11), TAN], ["leg", Vector3(-.15, .67, .36), Vector3(.11, .67, .11), TAN],
		["leg", Vector3(.15, .67, -.36), Vector3(.11, .67, .11), TAN], ["leg", Vector3(-.15, .67, -.36), Vector3(.11, .67, .11), TAN],
	],
	"duck": [
		["body", Vector3(0, .22, 0), Vector3(.3, .25, .42), FEATHER], ["rump", Vector3(0, .3, -.24), Vector3(.18, .08, .1), WING],
		["side", Vector3(.16, .24, -.02), Vector3(.04, .16, .3), WING], ["side", Vector3(-.16, .24, -.02), Vector3(.04, .16, .3), WING],
		["head", Vector3(0, .46, .17), Vector3(.18, .2, .18), GREEN], ["beak", Vector3(0, .42, .3), Vector3(.1, .05, .1), ORANGE],
		["eye", Vector3(.091, .5, .21), Vector3(.02, .04, .04), DARK], ["eye", Vector3(-.091, .5, .21), Vector3(.02, .04, .04), DARK],
		["leg", Vector3(.07, .1, .02), Vector3(.05, .1, .05), ORANGE], ["leg", Vector3(-.07, .1, .02), Vector3(.05, .1, .05), ORANGE],
	],
	# a round puff of fleece (any wool colour) with a dark face, amber eyes and curled horns
	"woolly": [
		["fleece", Vector3(0, .58, 0), Vector3(.86, .44, .9), VAR], ["fleece", Vector3(0, .86, -.02), Vector3(.7, .16, .76), VAR],
		["bobble", Vector3(0, .98, -.02), Vector3(.36, .1, .4), VAR], ["puff", Vector3(0, .68, -.5), Vector3(.2, .2, .1), VAR],
		["head", Vector3(0, .72, .54), Vector3(.3, .3, .26), SOOT], ["forelock", Vector3(0, .9, .52), Vector3(.34, .1, .3), VAR],
		["horn", Vector3(.2, .78, .5), Vector3(.08, .2, .2), HORN], ["horn", Vector3(-.2, .78, .5), Vector3(.08, .2, .2), HORN],
		["curl", Vector3(.22, .66, .6), Vector3(.08, .08, .1), HORN], ["curl", Vector3(-.22, .66, .6), Vector3(.08, .08, .1), HORN],
		["eye", Vector3(.08, .77, .671), Vector3(.06, .05, .02), AMBER], ["eye", Vector3(-.08, .77, .671), Vector3(.06, .05, .02), AMBER],
		["muzzle", Vector3(0, .64, .672), Vector3(.14, .08, .02), SOOT_LIGHT],
		["leg", Vector3(.24, .3, .28), Vector3(.12, .3, .12), SOOT], ["leg", Vector3(-.24, .3, .28), Vector3(.12, .3, .12), SOOT],
		["leg", Vector3(.24, .3, -.28), Vector3(.12, .3, .12), SOOT], ["leg", Vector3(-.24, .3, -.28), Vector3(.12, .3, .12), SOOT],
	],
	"hen": [
		["body", Vector3(0, .34, 0), Vector3(.34, .3, .42), HEN], ["breast", Vector3(0, .3, .21), Vector3(.28, .22, .04), CREAM],
		["head", Vector3(0, .58, .2), Vector3(.2, .22, .2), HEN], ["comb", Vector3(0, .72, .2), Vector3(.05, .08, .16), COMB],
		["beak", Vector3(0, .56, .33), Vector3(.08, .06, .08), BEAK], ["wattle", Vector3(0, .47, .31), Vector3(.05, .07, .03), COMB],
		["eye", Vector3(.101, .62, .25), Vector3(.02, .04, .04), DARK], ["eye", Vector3(-.101, .62, .25), Vector3(.02, .04, .04), DARK],
		["plume", Vector3(0, .52, -.22), Vector3(.22, .26, .08), HEN_DARK],
		["side", Vector3(.18, .36, -.02), Vector3(.04, .2, .3), HEN_DARK], ["side", Vector3(-.18, .36, -.02), Vector3(.04, .2, .3), HEN_DARK],
		["leg", Vector3(.08, .19, 0), Vector3(.05, .19, .05), BEAK], ["leg", Vector3(-.08, .19, 0), Vector3(.05, .19, .05), BEAK],
	],
	"goat": [
		["body", Vector3(0, .76, 0), Vector3(.42, .4, .8), GOAT], ["head", Vector3(0, 1.0, .48), Vector3(.24, .26, .3), GOAT],
		["horn", Vector3(.08, 1.2, .42), Vector3(.06, .18, .06), GOAT_DARK], ["horn", Vector3(-.08, 1.2, .42), Vector3(.06, .18, .06), GOAT_DARK],
		["horn", Vector3(.08, 1.27, .33), Vector3(.06, .06, .14), GOAT_DARK], ["horn", Vector3(-.08, 1.27, .33), Vector3(.06, .06, .14), GOAT_DARK],
		["beard", Vector3(0, .82, .6), Vector3(.08, .14, .06), GOAT_DARK],
		["ear", Vector3(.17, 1.04, .44), Vector3(.12, .05, .08), GOAT], ["ear", Vector3(-.17, 1.04, .44), Vector3(.12, .05, .08), GOAT],
		["eye", Vector3(.121, 1.05, .56), Vector3(.02, .05, .06), AMBER], ["eye", Vector3(-.121, 1.05, .56), Vector3(.02, .05, .06), AMBER],
		["nose", Vector3(0, .94, .632), Vector3(.12, .06, .02), GOAT_DARK], ["scut", Vector3(0, .92, -.42), Vector3(.08, .1, .06), GOAT],
		["leg", Vector3(.13, .56, .3), Vector3(.1, .56, .1), GOAT_DARK], ["leg", Vector3(-.13, .56, .3), Vector3(.1, .56, .1), GOAT_DARK],
		["leg", Vector3(.13, .56, -.3), Vector3(.1, .56, .1), GOAT_DARK], ["leg", Vector3(-.13, .56, -.3), Vector3(.1, .56, .1), GOAT_DARK],
	],
	"frog": [
		["body", Vector3(0, .15, 0), Vector3(.36, .2, .4), FROG], ["belly", Vector3(0, .05, .02), Vector3(.32, .04, .36), FROG_BELLY],
		["bulge", Vector3(.1, .29, .12), Vector3(.11, .1, .1), FROG], ["bulge", Vector3(-.1, .29, .12), Vector3(.11, .1, .1), FROG],
		["eye", Vector3(.1, .3, .171), Vector3(.06, .06, .02), DARK], ["eye", Vector3(-.1, .3, .171), Vector3(.06, .06, .02), DARK],
		["mouth", Vector3(0, .1, .201), Vector3(.24, .02, .02), Color8(50, 96, 40)],
		["haunch", Vector3(.2, .08, -.12), Vector3(.1, .12, .24), FROG], ["haunch", Vector3(-.2, .08, -.12), Vector3(.1, .12, .24), FROG],
		["foot", Vector3(.14, .03, .15), Vector3(.07, .06, .07), FROG], ["foot", Vector3(-.14, .03, .15), Vector3(.07, .06, .07), FROG],
	],
	"turtle": [
		["rim", Vector3(0, .15, 0), Vector3(.66, .06, .76), SHELL_RIM], ["shell", Vector3(0, .26, 0), Vector3(.58, .2, .68), SHELL],
		["dome", Vector3(0, .4, 0), Vector3(.42, .1, .5), SHELL_DARK], ["plate", Vector3(0, .456, 0), Vector3(.2, .02, .24), SHELL],
		["head", Vector3(0, .2, .44), Vector3(.18, .16, .2), TURTLE_SKIN],
		["eye", Vector3(.091, .23, .5), Vector3(.02, .04, .04), DARK], ["eye", Vector3(-.091, .23, .5), Vector3(.02, .04, .04), DARK],
		["stub", Vector3(0, .15, -.41), Vector3(.06, .06, .1), TURTLE_SKIN],
		["leg", Vector3(.27, .14, .24), Vector3(.14, .14, .14), TURTLE_SKIN], ["leg", Vector3(-.27, .14, .24), Vector3(.14, .14, .14), TURTLE_SKIN],
		["leg", Vector3(.27, .14, -.24), Vector3(.14, .14, .14), TURTLE_SKIN], ["leg", Vector3(-.27, .14, -.24), Vector3(.14, .14, .14), TURTLE_SKIN],
	],
	"lizard": [
		["body", Vector3(0, .12, 0), Vector3(.2, .12, .5), LIZARD], ["stripe", Vector3(0, .185, 0), Vector3(.08, .01, .44), LIZARD_DARK],
		["head", Vector3(0, .14, .33), Vector3(.16, .1, .18), LIZARD], ["dewlap", Vector3(0, .07, .35), Vector3(.08, .04, .12), DEWLAP],
		["eye", Vector3(.081, .17, .37), Vector3(.02, .03, .04), DARK], ["eye", Vector3(-.081, .17, .37), Vector3(.02, .03, .04), DARK],
		["tail", Vector3(0, .1, -.44), Vector3(.08, .06, .4), LIZARD_DARK],
		["leg", Vector3(.15, .08, .15), Vector3(.12, .08, .06), LIZARD_DARK], ["leg", Vector3(-.15, .08, .15), Vector3(.12, .08, .06), LIZARD_DARK],
		["leg", Vector3(.15, .08, -.15), Vector3(.12, .08, .06), LIZARD_DARK], ["leg", Vector3(-.15, .08, -.15), Vector3(.12, .08, .06), LIZARD_DARK],
	],
	"fish": [
		["body", Vector3(0, .15, 0), Vector3(.14, .2, .4), VAR], ["belly", Vector3(0, .06, .02), Vector3(.12, .04, .32), CREAM],
		["fin", Vector3(0, .28, -.02), Vector3(.03, .08, .18), VAR2],
		["eye", Vector3(.071, .18, .12), Vector3(.02, .04, .04), DARK], ["eye", Vector3(-.071, .18, .12), Vector3(.02, .04, .04), DARK],
		["tailfin", Vector3(0, .15, -.27), Vector3(.03, .2, .14), VAR2],
	],
	"bird": [
		["body", Vector3(0, 0, 0), Vector3(.16, .14, .3), VAR], ["head", Vector3(0, .06, .18), Vector3(.13, .13, .13), VAR],
		["beak", Vector3(0, .05, .28), Vector3(.04, .04, .07), BEAK], ["tail", Vector3(0, .02, -.22), Vector3(.1, .03, .14), VAR2],
		["eye", Vector3(.066, .08, .21), Vector3(.01, .03, .03), DARK], ["eye", Vector3(-.066, .08, .21), Vector3(.01, .03, .03), DARK],
		["wing", Vector3(.18, .03, 0), Vector3(.22, .02, .16), VAR2], ["wing", Vector3(-.18, .03, 0), Vector3(.22, .02, .16), VAR2],
	],
	"butterfly": [
		["body", Vector3(0, 0, 0), Vector3(.03, .03, .14), DARK],
		["wing", Vector3(.08, 0, .02), Vector3(.14, .01, .14), VAR], ["wing", Vector3(-.08, 0, .02), Vector3(.14, .01, .14), VAR],
		["wing", Vector3(.06, 0, -.07), Vector3(.1, .01, .08), VAR2], ["wing", Vector3(-.06, 0, -.07), Vector3(.1, .01, .08), VAR2],
	],
	"firefly": [
		["body", Vector3(0, 0, .02), Vector3(.04, .04, .07), DARK], ["glow", Vector3(0, -.005, -.045), Vector3(.07, .07, .07), FIREGLOW],
		["wing", Vector3(.03, .025, .01), Vector3(.05, .005, .04), WING_PALE], ["wing", Vector3(-.03, .025, .01), Vector3(.05, .005, .04), WING_PALE],
	],
	# the gloom: a tall, thin shadow with glowing eyes
	"cow": [
		["body", Vector3(0.0, 0.86, 0.0), Vector3(0.7, 0.62, 1.1), Color8(122, 84, 56)],
		["patch", Vector3(0.351, 0.95, 0.15), Vector3(0.02, 0.3, 0.36), Color8(232, 222, 200)],
		["patch", Vector3(-0.351, 0.8, -0.2), Vector3(0.02, 0.26, 0.3), Color8(232, 222, 200)],
		["udder", Vector3(0.0, 0.52, -0.25), Vector3(0.26, 0.1, 0.24), Color8(226, 160, 160)],
		["head", Vector3(0.0, 1.12, 0.66), Vector3(0.46, 0.42, 0.34), Color8(122, 84, 56)],
		["muzzle", Vector3(0.0, 1.0, 0.84), Vector3(0.34, 0.18, 0.04), Color8(232, 222, 200)],
		["horn", Vector3(0.27, 1.34, 0.62), Vector3(0.08, 0.14, 0.08), Color8(226, 216, 190)],
		["horn", Vector3(-0.27, 1.34, 0.62), Vector3(0.08, 0.14, 0.08), Color8(226, 216, 190)],
		["eye", Vector3(0.231, 1.18, 0.74), Vector3(0.02, 0.06, 0.06), Color8(31, 26, 23)],
		["eye", Vector3(-0.231, 1.18, 0.74), Vector3(0.02, 0.06, 0.06), Color8(31, 26, 23)],
		["tail", Vector3(0.0, 0.95, -0.56), Vector3(0.06, 0.4, 0.06), Color8(92, 62, 40)],
		["leg", Vector3(0.22, 0.55, 0.38), Vector3(0.18, 0.55, 0.18), Color8(92, 62, 40)],
		["leg", Vector3(-0.22, 0.55, 0.38), Vector3(0.18, 0.55, 0.18), Color8(92, 62, 40)],
		["leg", Vector3(0.22, 0.55, -0.38), Vector3(0.18, 0.55, 0.18), Color8(92, 62, 40)],
		["leg", Vector3(-0.22, 0.55, -0.38), Vector3(0.18, 0.55, 0.18), Color8(92, 62, 40)],
	],
	"cinder": [
		["body", Vector3(0.0, 0.35, 0.0), Vector3(0.8, 0.7, 0.8), Color8(58, 30, 26)],
		["crack", Vector3(0.401, 0.4, 0.1), Vector3(0.02, 0.4, 0.08), Color8(255, 140, 40)],
		["crack", Vector3(-0.401, 0.3, -0.15), Vector3(0.02, 0.3, 0.08), Color8(255, 140, 40)],
		["crack", Vector3(0.1, 0.701, 0.0), Vector3(0.4, 0.02, 0.08), Color8(255, 140, 40)],
		["crack", Vector3(-0.2, 0.5, 0.401), Vector3(0.08, 0.3, 0.02), Color8(255, 140, 40)],
		["glow", Vector3(0.18, 0.5, 0.405), Vector3(0.14, 0.1, 0.02), Color8(255, 220, 90)],
		["glow", Vector3(-0.18, 0.5, 0.405), Vector3(0.14, 0.1, 0.02), Color8(255, 220, 90)],
		["mouth", Vector3(0.0, 0.25, 0.405), Vector3(0.36, 0.06, 0.02), Color8(255, 100, 30)],
	],
	"pig": [
		["body", Vector3(0.0, 0.45, 0.0), Vector3(0.6, 0.5, 0.9), Color8(232, 166, 166)],
		["head", Vector3(0.0, 0.6, 0.55), Vector3(0.5, 0.45, 0.4), Color8(232, 166, 166)],
		["snout", Vector3(0.0, 0.52, 0.77), Vector3(0.24, 0.16, 0.06), Color8(212, 124, 132)],
		["eye", Vector3(0.13, 0.68, 0.751), Vector3(0.06, 0.06, 0.02), Color8(31, 26, 23)],
		["eye", Vector3(-0.13, 0.68, 0.751), Vector3(0.06, 0.06, 0.02), Color8(31, 26, 23)],
		["ear", Vector3(0.17, 0.86, 0.5), Vector3(0.12, 0.1, 0.06), Color8(212, 124, 132)],
		["ear", Vector3(-0.17, 0.86, 0.5), Vector3(0.12, 0.1, 0.06), Color8(212, 124, 132)],
		["tail", Vector3(0.0, 0.6, -0.47), Vector3(0.06, 0.06, 0.06), Color8(212, 124, 132)],
		["leg", Vector3(0.17, 0.25, 0.3), Vector3(0.16, 0.25, 0.16), Color8(232, 166, 166)],
		["leg", Vector3(-0.17, 0.25, 0.3), Vector3(0.16, 0.25, 0.16), Color8(232, 166, 166)],
		["leg", Vector3(0.17, 0.25, -0.3), Vector3(0.16, 0.25, 0.16), Color8(232, 166, 166)],
		["leg", Vector3(-0.17, 0.25, -0.3), Vector3(0.16, 0.25, 0.16), Color8(232, 166, 166)],
	],
	"horse": [
		["body", Vector3(0.0, 1.1, 0.0), Vector3(0.6, 0.6, 1.3), VAR],
		["neck", Vector3(0.0, 1.5, 0.6), Vector3(0.3, 0.6, 0.3), VAR],
		["head", Vector3(0.0, 1.8, 0.85), Vector3(0.3, 0.3, 0.55), VAR],
		["muzzle", Vector3(0.0, 1.72, 1.1), Vector3(0.26, 0.2, 0.06), VAR2],
		["mane", Vector3(0.0, 1.65, 0.48), Vector3(0.1, 0.7, 0.2), Color8(52, 36, 26)],
		["eye", Vector3(0.151, 1.85, 0.9), Vector3(0.02, 0.06, 0.06), Color8(31, 26, 23)],
		["eye", Vector3(-0.151, 1.85, 0.9), Vector3(0.02, 0.06, 0.06), Color8(31, 26, 23)],
		["ear", Vector3(0.09, 2.0, 0.7), Vector3(0.06, 0.14, 0.06), VAR],
		["ear", Vector3(-0.09, 2.0, 0.7), Vector3(0.06, 0.14, 0.06), VAR],
		["tail", Vector3(0.0, 1.15, -0.7), Vector3(0.12, 0.55, 0.1), Color8(52, 36, 26)],
		["leg", Vector3(0.2, 0.8, 0.45), Vector3(0.18, 0.8, 0.18), VAR],
		["leg", Vector3(-0.2, 0.8, 0.45), Vector3(0.18, 0.8, 0.18), VAR],
		["leg", Vector3(0.2, 0.8, -0.45), Vector3(0.18, 0.8, 0.18), VAR],
		["leg", Vector3(-0.2, 0.8, -0.45), Vector3(0.18, 0.8, 0.18), VAR],
	],
	"archer": [
		["body", Vector3(0.0, 1.05, 0.0), Vector3(0.36, 0.6, 0.2), Color8(214, 210, 196)],
		["rib", Vector3(0.0, 1.1, 0.101), Vector3(0.3, 0.04, 0.02), Color8(150, 146, 136)],
		["rib", Vector3(0.0, 0.95, 0.101), Vector3(0.3, 0.04, 0.02), Color8(150, 146, 136)],
		["head", Vector3(0.0, 1.6, 0.0), Vector3(0.42, 0.42, 0.42), Color8(214, 210, 196)],
		["eye", Vector3(0.1, 1.62, 0.211), Vector3(0.1, 0.08, 0.02), Color8(31, 26, 23)],
		["eye", Vector3(-0.1, 1.62, 0.211), Vector3(0.1, 0.08, 0.02), Color8(31, 26, 23)],
		["bow", Vector3(0.3, 1.0, 0.25), Vector3(0.04, 0.7, 0.06), Color8(120, 84, 50)],
		["leg", Vector3(0.26, 1.38, 0.0), Vector3(0.1, 0.65, 0.1), Color8(214, 210, 196)],
		["leg", Vector3(-0.26, 1.38, 0.0), Vector3(0.1, 0.65, 0.1), Color8(214, 210, 196)],
		["leg", Vector3(0.1, 0.75, 0.0), Vector3(0.12, 0.75, 0.12), Color8(214, 210, 196)],
		["leg", Vector3(-0.1, 0.75, 0.0), Vector3(0.12, 0.75, 0.12), Color8(214, 210, 196)],
	],
	"beetle": [
		["body", Vector3(0.0, 0.4, 0.0), Vector3(0.8, 0.5, 1.0), Color8(30, 30, 36)],
		["top", Vector3(0.0, 0.7, -0.05), Vector3(0.6, 0.16, 0.8), Color8(60, 60, 70)],
		["head", Vector3(0.0, 0.35, 0.6), Vector3(0.44, 0.3, 0.24), Color8(60, 60, 70)],
		["eye", Vector3(0.12, 0.4, 0.721), Vector3(0.08, 0.08, 0.02), Color8(255, 80, 60)],
		["eye", Vector3(-0.12, 0.4, 0.721), Vector3(0.08, 0.08, 0.02), Color8(255, 80, 60)],
		["fuse", Vector3(0.0, 0.86, -0.2), Vector3(0.06, 0.24, 0.06), Color8(200, 170, 110)],
		["glow", Vector3(0.0, 1.0, -0.2), Vector3(0.1, 0.1, 0.1), Color8(255, 180, 60)],
		["leg", Vector3(0.45, 0.2, 0.3), Vector3(0.08, 0.2, 0.08), Color8(30, 30, 36)],
		["leg", Vector3(-0.45, 0.2, 0.3), Vector3(0.08, 0.2, 0.08), Color8(30, 30, 36)],
		["leg", Vector3(0.45, 0.2, 0.0), Vector3(0.08, 0.2, 0.08), Color8(30, 30, 36)],
		["leg", Vector3(-0.45, 0.2, 0.0), Vector3(0.08, 0.2, 0.08), Color8(30, 30, 36)],
		["leg", Vector3(0.45, 0.2, -0.3), Vector3(0.08, 0.2, 0.08), Color8(30, 30, 36)],
		["leg", Vector3(-0.45, 0.2, -0.3), Vector3(0.08, 0.2, 0.08), Color8(30, 30, 36)],
	],
	"wolf": [
		["body", Vector3(0.0, 0.6, 0.0), Vector3(0.4, 0.42, 0.85), Color8(150, 150, 150)],
		["mane", Vector3(0.0, 0.66, 0.3), Vector3(0.48, 0.5, 0.3), Color8(110, 110, 112)],
		["head", Vector3(0.0, 0.75, 0.6), Vector3(0.34, 0.32, 0.3), Color8(150, 150, 150)],
		["snout", Vector3(0.0, 0.68, 0.8), Vector3(0.18, 0.14, 0.16), Color8(220, 216, 206)],
		["nose", Vector3(0.0, 0.72, 0.881), Vector3(0.06, 0.05, 0.02), Color8(31, 26, 23)],
		["eye", Vector3(0.09, 0.8, 0.751), Vector3(0.06, 0.04, 0.02), Color8(31, 26, 23)],
		["eye", Vector3(-0.09, 0.8, 0.751), Vector3(0.06, 0.04, 0.02), Color8(31, 26, 23)],
		["ear", Vector3(0.1, 0.95, 0.55), Vector3(0.08, 0.1, 0.06), Color8(110, 110, 112)],
		["ear", Vector3(-0.1, 0.95, 0.55), Vector3(0.08, 0.1, 0.06), Color8(110, 110, 112)],
		["tail", Vector3(0.0, 0.7, -0.45), Vector3(0.1, 0.1, 0.35), Color8(110, 110, 112)],
		["leg", Vector3(0.13, 0.4, 0.3), Vector3(0.11, 0.4, 0.11), Color8(150, 150, 150)],
		["leg", Vector3(-0.13, 0.4, 0.3), Vector3(0.11, 0.4, 0.11), Color8(150, 150, 150)],
		["leg", Vector3(0.13, 0.4, -0.3), Vector3(0.11, 0.4, 0.11), Color8(150, 150, 150)],
		["leg", Vector3(-0.13, 0.4, -0.3), Vector3(0.11, 0.4, 0.11), Color8(150, 150, 150)],
	],
	"guard": [
		["body", Vector3(0.0, 1.5, 0.0), Vector3(0.9, 0.9, 0.5), Color8(176, 178, 184)],
		["belly", Vector3(0.0, 1.0, 0.0), Vector3(0.6, 0.3, 0.4), Color8(120, 122, 130)],
		["head", Vector3(0.0, 2.2, 0.0), Vector3(0.45, 0.45, 0.45), Color8(176, 178, 184)],
		["glow", Vector3(0.0, 2.22, 0.231), Vector3(0.36, 0.08, 0.02), Color8(120, 230, 255)],
		["moss", Vector3(0.3, 1.75, 0.255), Vector3(0.2, 0.12, 0.02), Color8(80, 140, 60)],
		["bolt", Vector3(-0.3, 1.3, 0.255), Vector3(0.08, 0.08, 0.02), Color8(120, 122, 130)],
		["leg", Vector3(0.6, 1.9, 0.0), Vector3(0.25, 1.3, 0.25), Color8(176, 178, 184)],
		["leg", Vector3(-0.6, 1.9, 0.0), Vector3(0.25, 1.3, 0.25), Color8(176, 178, 184)],
		["leg", Vector3(0.2, 0.85, 0.0), Vector3(0.3, 0.85, 0.3), Color8(120, 122, 130)],
		["leg", Vector3(-0.2, 0.85, 0.0), Vector3(0.3, 0.85, 0.3), Color8(120, 122, 130)],
	],
	"bee": [
		["body", Vector3(0.0, 0.0, 0.0), Vector3(0.24, 0.22, 0.32), Color8(240, 200, 40)],
		["stripe", Vector3(0.0, 0.0, -0.04), Vector3(0.25, 0.23, 0.06), Color8(40, 30, 20)],
		["stripe", Vector3(0.0, 0.0, 0.08), Vector3(0.25, 0.23, 0.05), Color8(40, 30, 20)],
		["eye", Vector3(0.06, 0.04, 0.161), Vector3(0.05, 0.05, 0.02), Color8(40, 30, 20)],
		["eye", Vector3(-0.06, 0.04, 0.161), Vector3(0.05, 0.05, 0.02), Color8(40, 30, 20)],
		["sting", Vector3(0.0, 0.0, -0.18), Vector3(0.03, 0.03, 0.05), Color8(40, 30, 20)],
		["wing", Vector3(0.06, 0.13, 0.0), Vector3(0.16, 0.02, 0.12), Color8(230, 240, 250)],
		["wing", Vector3(-0.06, 0.13, 0.0), Vector3(0.16, 0.02, 0.12), Color8(230, 240, 250)],
	],
	# a worker: a person in a shirt of their trade's colour, overalls and a cap
	"worker": [
		["body", Vector3(0, 1.08, 0), Vector3(.5, .72, .28), VAR], ["bib", Vector3(0, .98, .145), Vector3(.34, .5, .02), PANTS],
		["strap", Vector3(.13, 1.32, .145), Vector3(.06, .2, .02), PANTS], ["strap", Vector3(-.13, 1.32, .145), Vector3(.06, .2, .02), PANTS],
		["belt", Vector3(0, .74, 0), Vector3(.52, .08, .3), BOOT],
		["head", Vector3(0, 1.66, 0), Vector3(.42, .42, .42), SKIN], ["hair", Vector3(0, 1.8, -.04), Vector3(.44, .16, .38), HAIR],
		["cap", Vector3(0, 1.91, 0), Vector3(.46, .1, .46), VAR2], ["brim", Vector3(0, 1.88, .27), Vector3(.46, .04, .14), VAR2],
		["eye", Vector3(.1, 1.7, .211), Vector3(.08, .06, .02), DARK], ["eye", Vector3(-.1, 1.7, .211), Vector3(.08, .06, .02), DARK],
		["nose", Vector3(0, 1.6, .24), Vector3(.08, .12, .06), SKIN_DARK], ["mouth", Vector3(0, 1.53, .211), Vector3(.14, .03, .02), SKIN_DARK],
		["leg", Vector3(.33, 1.42, 0), Vector3(.14, .62, .14), VAR], ["leg", Vector3(-.33, 1.42, 0), Vector3(.14, .62, .14), VAR],
		["leg", Vector3(.12, .72, 0), Vector3(.2, .72, .22), PANTS], ["leg", Vector3(-.12, .72, 0), Vector3(.2, .72, .22), PANTS],
	],
	"gloom": [
		["body", Vector3(0, 1.0, 0), Vector3(.5, .8, .3), SHADOW], ["head", Vector3(0, 1.62, 0), Vector3(.44, .4, .4), SHADOW_EDGE],
		["glow", Vector3(.1, 1.66, .205), Vector3(.1, .06, .02), GLOW], ["glow", Vector3(-.1, 1.66, .205), Vector3(.1, .06, .02), GLOW],
		["arm", Vector3(.33, 1.0, .05), Vector3(.12, .75, .12), SHADOW_EDGE], ["arm", Vector3(-.33, 1.0, .05), Vector3(.12, .75, .12), SHADOW_EDGE],
		["leg", Vector3(.12, .6, 0), Vector3(.16, .6, .16), SHADOW], ["leg", Vector3(-.12, .6, 0), Vector3(.16, .6, .16), SHADOW],
	],
	# the bramble: a low mound of thorny vines on six stubby legs, with ember eyes
	"bramble": [
		["body", Vector3(0, .38, 0), Vector3(.9, .4, .9), BRAMBLE], ["top", Vector3(0, .64, -.04), Vector3(.62, .16, .62), BRAMBLE_DARK],
		["knot", Vector3(.12, .76, .08), Vector3(.22, .1, .22), BRAMBLE],
		["thorn", Vector3(.49, .42, .2), Vector3(.1, .05, .05), THORN], ["thorn", Vector3(-.49, .46, -.12), Vector3(.1, .05, .05), THORN],
		["thorn", Vector3(.49, .36, -.26), Vector3(.1, .05, .05), THORN], ["thorn", Vector3(-.49, .34, .26), Vector3(.1, .05, .05), THORN],
		["thorn", Vector3(.22, .76, -.18), Vector3(.05, .12, .05), THORN], ["thorn", Vector3(-.18, .78, .14), Vector3(.05, .12, .05), THORN],
		["thorn", Vector3(.04, .86, .1), Vector3(.05, .1, .05), THORN], ["thorn", Vector3(-.1, .44, -.49), Vector3(.05, .05, .1), THORN],
		["glow", Vector3(.2, .46, .451), Vector3(.12, .07, .02), EMBER], ["glow", Vector3(-.2, .46, .451), Vector3(.12, .07, .02), EMBER],
		["maw", Vector3(0, .28, .451), Vector3(.36, .05, .02), Color8(26, 20, 14)],
		["leg", Vector3(.36, .2, .3), Vector3(.12, .2, .12), BRAMBLE_DARK], ["leg", Vector3(-.36, .2, .3), Vector3(.12, .2, .12), BRAMBLE_DARK],
		["leg", Vector3(.36, .2, 0), Vector3(.12, .2, .12), BRAMBLE_DARK], ["leg", Vector3(-.36, .2, 0), Vector3(.12, .2, .12), BRAMBLE_DARK],
		["leg", Vector3(.36, .2, -.3), Vector3(.12, .2, .12), BRAMBLE_DARK], ["leg", Vector3(-.36, .2, -.3), Vector3(.12, .2, .12), BRAMBLE_DARK],
	],
	# the bog glob: a squat mossy mound with one glowing eye on a stalk and a toothy grin
	"glob": [
		["base", Vector3(0, .25, 0), Vector3(1.0, .5, .9), GLOB], ["top", Vector3(0, .62, 0), Vector3(.72, .26, .66), GLOB],
		["moss", Vector3(0, .76, 0), Vector3(.5, .04, .5), GLOB_TOP], ["stalk", Vector3(0, .84, .1), Vector3(.08, .16, .08), GLOB_TOP],
		["white", Vector3(0, .98, .12), Vector3(.2, .16, .16), EYE_WHITE], ["glow", Vector3(0, .98, .205), Vector3(.1, .1, .02), PUPIL],
		["drip", Vector3(.36, .3, .46), Vector3(.1, .2, .04), GLOB_TOP], ["drip", Vector3(-.4, .2, -.46), Vector3(.1, .2, .04), GLOB_TOP],
		["mouth", Vector3(0, .3, .451), Vector3(.5, .06, .02), Color8(36, 52, 30)],
		["tooth", Vector3(.12, .255, .455), Vector3(.06, .05, .02), THORN], ["tooth", Vector3(-.12, .255, .455), Vector3(.06, .05, .02), THORN],
	],
}

static var _cube_v := PackedVector3Array()
static var _cube_s := PackedFloat32Array()
static var _meshes := {}         # "kind:variant" -> [still body mesh, glow mesh or null, [[name, pivot, mesh, sign]]]
static var _levels := []         # shared materials for quantised brightness, plus [LEVELS] = hurt red
static var _glow_mat: StandardMaterial3D
const LEVELS := 16

var animal
var body := Node3D.new()
var _still: MeshInstance3D
var _glow: MeshInstance3D = null
var _shaded := []               # mesh instances that take the brightness material
var legs := []
var wings := []                 # [pivot, sign]
var tails := []
var _light_timer := 0.0
var _level := -1
var _seen := true
var _base_scale := 1.0


static func _setup() -> void:
	if not _cube_v.is_empty():
		return
	Mesher._static_setup()
	for f in 6:
		var shade: float = Mesher.FACES[f][1]
		for c in Mesher.face_corners[f]:
			_cube_v.append(c)
			_cube_s.append(shade)
	for i in LEVELS + 2:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.vertex_color_use_as_albedo = true
		var b := 0.07 + 0.93 * float(i) / LEVELS
		m.albedo_color = Color(1, 0.25, 0.25) if i > LEVELS else Color(b, b, b)
		_levels.append(m)
	_glow_mat = StandardMaterial3D.new()
	_glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glow_mat.vertex_color_use_as_albedo = true


## A unit cube with the terrain's face shading (kept for other scripts).
static func box_mesh() -> ArrayMesh:
	return _boxes([[Vector3.ZERO, Vector3.ONE, Color.WHITE]])


static func _boxes(list: Array) -> ArrayMesh:
	_setup()
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	for b in list:
		var at: Vector3 = b[0]
		var size: Vector3 = b[1]
		var col: Color = b[2]
		for i in _cube_v.size():
			verts.append(_cube_v[i] * size + at)
			var s := _cube_s[i]
			cols.append(Color(col.r * s, col.g * s, col.b * s))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = cols
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


const SHEARED := 99                # a woolly sheep's "colour" while its fleece grows back


static func variant_colour(kind: String, variant: int) -> Color:
	if kind == "woolly" and variant == SHEARED:
		return Color8(214, 184, 160)         # bare pink-brown skin
	if kind == "woolly":
		var dyes: Array = Blocks.dyes
		if variant >= 0 and variant < dyes.size():
			var rgb: Array = dyes[variant][1]
			var c := Color8(int(rgb[0]), int(rgb[1]), int(rgb[2]))
			return c.lerp(Color.WHITE, 0.12)      # fleece is a little softer than the wool block
		return Color.WHITE
	var pal: Array = PALETTES.get(kind, [Color.WHITE])
	return pal[clampi(variant, 0, pal.size() - 1)]


## The shared meshes of one species in one colour.
static func meshes_for(kind: String, variant: int) -> Array:
	var key := "%s:%d" % [kind, variant]
	if _meshes.has(key):
		return _meshes[key]
	var main_col := variant_colour(kind, variant)
	var dark_col := main_col.darkened(0.3)
	var still := []
	var glow := []
	var moving := []
	for p in MODELS[SAME_AS.get(kind, kind)]:
		var name: String = p[0]
		var at: Vector3 = p[1]
		var size: Vector3 = p[2]
		var col: Color = p[3]
		if col == VAR:
			col = main_col
		elif col == VAR2:
			col = dark_col
		if name == "leg":                      # hangs from the hip
			moving.append([name, at, _boxes([[Vector3(0, -size.y / 2, 0), size, col]]), 1.0])
		elif name == "wing":                   # hinged at the inner edge
			var sgn := 1.0 if at.x >= 0 else -1.0
			moving.append([name, at - Vector3(sgn * size.x / 2, 0, 0), _boxes([[Vector3(sgn * size.x / 2, 0, 0), size, col]]), sgn])
		elif name == "tailfin":                # hinged at the front
			moving.append([name, at + Vector3(0, 0, size.z / 2), _boxes([[Vector3(0, 0, -size.z / 2), size, col]]), 1.0])
		elif name == "glow":
			glow.append([at, size, col])
		else:
			still.append([at, size, col])
	var out := [_boxes(still), _boxes(glow) if not glow.is_empty() else null, moving]
	_meshes[key] = out
	return out


var shorn := false                  # drawn without its fleece


func _init(a) -> void:
	animal = a
	_setup()
	add_child(body)
	shorn = a.kind == "woolly" and a.sheared > 0
	var m: Array = meshes_for(a.kind, SHEARED if shorn else a.variant)
	_still = MeshInstance3D.new()
	_still.mesh = m[0]
	body.add_child(_still)
	_shaded.append(_still)
	if m[1] != null:
		_glow = MeshInstance3D.new()
		_glow.mesh = m[1]
		_glow.material_override = _glow_mat
		body.add_child(_glow)
	for part in m[2]:
		var pivot := Node3D.new()
		pivot.position = part[1]
		var mi := MeshInstance3D.new()
		mi.mesh = part[2]
		pivot.add_child(mi)
		body.add_child(pivot)
		_shaded.append(mi)
		match part[0]:
			"leg":
				legs.append(pivot)
			"wing":
				wings.append([pivot, part[3]])
			_:
				tails.append(pivot)
	_base_scale = SCALES.get(a.kind, 1.0)
	_set_level(LEVELS)


func _set_level(level: int) -> void:
	if level == _level:
		return
	_level = level
	var m: StandardMaterial3D = _levels[level]
	for mi: MeshInstance3D in _shaded:
		mi.material_override = m


func sync(dt: float, daylight: float, world: WorldData) -> void:
	var a = animal
	var seen: bool = not a.hidden
	if seen != _seen:
		_seen = seen
		visible = seen
	if not seen:
		return
	position = a.pos
	rotation.y = deg_to_rad(a.yaw)
	var s: float = _base_scale * (Wildlife.BABY_SCALE if a.age > 0 else 1.0)
	if scale.x != s:
		scale = Vector3(s, s, s)
	var phase: float = a.walk_phase
	var swing: float = sin(phase) if a.moving else 0.0
	for i in legs.size():
		legs[i].rotation.x = swing * 0.6 * (1 if i % 2 == (i / 2) % 2 else -1)
	if not wings.is_empty():
		var flap := sin(phase) * (0.9 if a.kind == "butterfly" else 0.6)
		for w in wings:
			w[0].rotation.z = flap * w[1]
	for t: Node3D in tails:
		t.rotation.y = sin(phase) * 0.5
	if a.kind == "rabbit":
		body.position.y = absf(sin(phase * 0.5)) * 0.18 if a.moving else 0.0
	elif a.kind == "firefly" and _glow != null:
		_glow.visible = sin(phase * 0.21 + a.slot) > -0.4
	_light_timer -= dt
	if a.hurt_time > 0:
		_set_level(LEVELS + 1)
		_light_timer = 0
	elif a.fade > 0:                             # dissolving in the sun: shrink away
		body.scale = Vector3.ONE * clampf(a.fade / 2.0, 0.05, 1.0)
	elif _light_timer <= 0:
		_light_timer = 0.3 + 0.05 * (a.slot % 3)
		var col = world.column(Wildlife.cell(a.pos.x), Wildlife.cell(a.pos.z))
		var open_sky: bool = col != null and Wildlife.cell(a.pos.y + 0.3) > col[0]
		var b := maxf(daylight * (1.0 if open_sky else 0.3), 0.07)
		_set_level(clampi(roundi((b - 0.07) / 0.93 * LEVELS), 0, LEVELS))


## Distance along a ray to this animal's body (a rough box), or -1 if the ray misses.
## Ambient creatures (birds, butterflies, fireflies) can't be hit.
func ray_hit(origin: Vector3, dir: Vector3, max_distance: float) -> float:
	if animal.ambient or animal.hidden:
		return -1.0
	var k: float = Wildlife.BABY_SCALE if animal.age > 0 else 1.0
	var h: float = animal.spec["height"] * k
	var w: float = animal.spec["width"] * k / 2.0 + 0.1
	var aabb := AABB(animal.pos + Vector3(-w, 0, -w), Vector3(w * 2, h, w * 2))
	var hit = aabb.intersects_ray(origin, dir)
	if hit == null:
		return -1.0
	var d := origin.distance_to(hit)
	return d if d <= max_distance else -1.0
