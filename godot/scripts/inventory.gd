class_name Inventory
extends RefCounted
## Slots hold [item, count] (tools: [item, 1, durability]) or null. Slots 0-8 are the hotbar.
## Port of the Inventory class in inventory.py.

const HOTBAR := 9
var slots := []


func _init(size := 36) -> void:
	slots.resize(size)


func count(item) -> int:
	var members: Array = Items.groups.get(item, [item]) if item is String else [item]
	var n := 0
	for s in slots:
		if s != null and s[0] in members:
			n += s[1]
	return n


func item_at(i: int) -> int:
	return slots[i][0] if slots[i] != null else 0


## Add items, topping up existing stacks first. Returns how many did not fit.
func add(item: int, amount := 1) -> int:
	var limit := Items.max_stack(item)
	for i in slots.size():
		var s = slots[i]
		if amount > 0 and s != null and s[0] == item and s[1] < limit:
			var moved := mini(amount, limit - s[1])
			slots[i] = [item, s[1] + moved]
			amount -= moved
	for i in slots.size():
		if amount > 0 and slots[i] == null:
			var moved := mini(amount, limit)
			slots[i] = Items.new_stack(item, moved)
			amount -= moved
	return amount


## Remove exactly `amount` (storage slots first). All or nothing. Works with groups too.
func remove(item, amount := 1) -> bool:
	if count(item) < amount:
		return false
	if item is String:
		for member in Items.groups[item]:
			var take := mini(amount, count(member))
			if take > 0:
				remove(member, take)
				amount -= take
		return true
	for i in range(slots.size() - 1, -1, -1):
		var s = slots[i]
		if amount > 0 and s != null and s[0] == item:
			var taken := mini(amount, s[1])
			slots[i] = [item, s[1] - taken] if s[1] > taken else null
			amount -= taken
	return true


func use_one(i: int) -> int:
	var s = slots[i]
	if s == null:
		return 0
	slots[i] = [s[0], s[1] - 1] if s[1] > 1 else null
	return s[0]


## One point of tool wear. Returns true if the tool broke.
func wear(i: int) -> bool:
	var s = slots[i]
	if s == null or s.size() < 3:
		return false
	if s.size() > 3 and str(s[3]) == "unbreaking" and randf() < 0.5:
		return false                                   # enchanted: wears out half as fast
	if s[2] <= 1:
		slots[i] = null
		return true
	slots[i] = [s[0], 1, s[2] - 1] + (s.slice(3) if s.size() > 3 else [])
	return false


## The enchantment on a slot's tool or armour ("" if none).
func enchant_of(i: int) -> String:
	var s = slots[i]
	return str(s[3]) if s != null and s.size() > 3 else ""


## Tap a slot while holding `cursor` (a stack or null). Returns the new cursor.
## half: take half a stack / put down one (right click, or the "split" toggle on phones).
func click(i: int, cursor, half := false):
	var slot = slots[i]
	if not half:
		if cursor == null:
			slots[i] = null
			return slot
		if slot == null:
			slots[i] = cursor
			return null
		if slot[0] == cursor[0] and Items.max_stack(slot[0]) > 1:
			var moved := mini(cursor[1], Items.STACK_SIZE - slot[1])
			slots[i] = [slot[0], slot[1] + moved]
			var rest: int = cursor[1] - moved
			return [cursor[0], rest] if rest > 0 else null
		slots[i] = cursor
		return slot
	if cursor == null:
		if slot == null:
			return null
		var take: int = (slot[1] + 1) / 2
		if take == slot[1]:
			slots[i] = null
			return slot
		slots[i] = [slot[0], slot[1] - take]
		return [slot[0], take]
	if slot == null and cursor[1] == 1:
		slots[i] = cursor
		return null
	if slot == null or (slot[0] == cursor[0] and slot[1] < Items.max_stack(slot[0])):
		slots[i] = [cursor[0], (slot[1] if slot != null else 0) + 1]
		return [cursor[0], cursor[1] - 1] if cursor[1] > 1 else null
	return cursor


## Move a stack between the hotbar and the storage area.
func quick_move(i: int) -> void:
	var s = slots[i]
	if s == null:
		return
	var target := range(HOTBAR, slots.size()) if i < HOTBAR else range(HOTBAR)
	var amount: int = s[1]
	slots[i] = null
	for j in target:
		var t = slots[j]
		if amount > 0 and t != null and t[0] == s[0] and t[1] < Items.max_stack(s[0]):
			var moved := mini(amount, Items.STACK_SIZE - t[1])
			slots[j] = [s[0], t[1] + moved]
			amount -= moved
	for j in target:
		if amount > 0 and slots[j] == null:
			slots[j] = s if amount == s[1] else [s[0], amount]
			amount = 0
	if amount > 0:
		slots[i] = s if amount == s[1] else [s[0], amount]


## Put a whole stack in (tools keep durability). Returns what didn't fit, or null.
func give(stack):
	if stack.size() == 3:
		for i in slots.size():
			if slots[i] == null:
				slots[i] = stack
				return null
		return stack
	var left := add(stack[0], stack[1])
	return [stack[0], left] if left > 0 else null


## True if at least part of the stack fits.
func can_take(stack: Array) -> bool:
	for s in slots:
		if s == null:
			return true
		if s[0] == stack[0] and s.size() < 3 and stack.size() < 3 and s[1] < Items.max_stack(s[0]):
			return true
	return false


func can_craft(r: Dictionary) -> bool:
	for k in r["in"]:
		if count(k) < r["in"][k]:
			return false
	return true


## Craft once. Nothing changes if ingredients are missing or the result doesn't fit.
func craft(r: Dictionary) -> bool:
	if not can_craft(r):
		return false
	var before := slots.duplicate(true)
	for k in r["in"]:
		remove(k, r["in"][k])
	if add(r["out"][0], r["out"][1]) > 0:
		slots = before
		return false
	for k in r["in"]:
		if not k is String and Items.returns.has(int(k)) and add(Items.returns[int(k)], int(r["in"][k])) > 0:
			slots = before                        # no room for the empty bucket
			return false
	return true


func to_data() -> Array:
	return slots.duplicate(true)


static func from_data(data, size := 36) -> Inventory:
	var inv := Inventory.new(size)
	if data is Array:
		for i in mini(data.size(), size):
			if data[i] is Array:
				inv.slots[i] = data[i].map(func(v): return int(v))
	return inv
