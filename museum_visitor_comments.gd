extends RefCounted

# Comments describe only a displayed, registered specimen. They carry no
# economy promises and never introduce lore, rarity or a price that is not in
# the collection model.
const NAMES := {"crystal_small": "小晶石", "crystal_medium": "晶石簇", "crystal_large": "大晶石",
	"chest": "宝箱", "shield": "盾牌", "hammer": "战锤"}
const REACTIONS := {
	"crystal_small": ["小小晶石，很精巧。", "这颗小晶石真可爱！", "小晶石的棱角真多。"],
	"crystal_medium": ["晶体都长在一起呢。", "晶石簇的轮廓真有趣。", "晶石簇层次分明。"],
	"crystal_large": ["这块大晶石真醒目！", "好大一块晶石！", "大晶石的尖角真漂亮。"],
	"chest": ["宝箱的锁扣真有趣。", "宝箱上的纹理很特别。", "想绕着宝箱再看看。"],
	"shield": ["盾牌的外形真有气势。", "这面盾牌很吸引人。", "盾牌的边缘真特别。"],
	"hammer": ["这把战锤看着很厚实。", "战锤的锤头真醒目。", "战锤的轮廓真特别。"],
}

static func category_for(entry: Dictionary) -> String:
	var item: Dictionary = entry.get("item", {})
	if item.is_empty():
		return ""
	var kind := str(item.get("item_type", ""))
	if kind != "crystal":
		return kind if NAMES.has(kind) else ""
	var footprint: Variant = item.get("footprint", Vector2i.ZERO)
	if footprint == Vector2i.ONE:
		return "crystal_small"
	if footprint == Vector2i(1, 2):
		return "crystal_medium"
	if footprint == Vector2i(2, 2):
		return "crystal_large"
	return ""

static func comment_for(entry: Dictionary, variant: int = 0) -> String:
	var category := category_for(entry)
	if category.is_empty():
		return empty_comment(variant)
	var item: Dictionary = entry.item
	var wear := clampi(int(item.get("wear", 0)), 0, 100)
	var level := clampi(int(entry.get("level", 1)), 1, 3)
	var index := posmod(variant, 3)
	var text: String = REACTIONS[category][index]
	var condition: String
	if wear >= 35:
		condition = ["磨痕很明显。", "磨痕明显，讲解详细。", "磨痕明显，研究深入。"][level - 1]
	elif wear <= 8:
		condition = ["保存得真好！", "保存完好，讲解详细。", "保存完好，研究深入。"][level - 1]
	else:
		condition = ["值得多看几眼。", "解说也很详细。", "研究资料真丰富！"][level - 1]
	return text + "\n" + condition

static func empty_comment(variant: int = 0) -> String:
	return ["还在布展呀，\n期待新的发现。", "下次会展出什么呢？", "先逛一逛，\n等新展品上架。"][posmod(variant, 3)]
