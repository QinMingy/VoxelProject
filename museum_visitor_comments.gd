extends RefCounted

# Comments describe only a displayed, registered specimen. They carry no
# economy promises and never introduce lore, rarity or a price that is not in
# the collection model.
const NAMES := {"crystal_small": "小晶石", "crystal_medium": "晶石簇", "crystal_large": "大晶石",
	"chest": "宝箱", "shield": "盾牌", "hammer": "战锤", "spellbook": "魔法书", "chest_large": "大箱子"}
const REACTIONS := {
	"crystal_small": ["小小晶石，很精巧。", "这颗小晶石真可爱！", "小晶石的棱角真多。"],
	"crystal_medium": ["晶体都长在一起呢。", "晶石簇的轮廓真有趣。", "晶石簇层次分明。"],
	"crystal_large": ["这块大晶石真醒目！", "好大一块晶石！", "大晶石的尖角真漂亮。"],
	"chest": ["宝箱的锁扣真有趣。", "宝箱上的纹理很特别。", "想绕着宝箱再看看。"],
	"shield": ["盾牌的外形真有气势。", "这面盾牌很吸引人。", "盾牌的边缘真特别。"],
	"hammer": ["这把战锤看着很厚实。", "战锤的锤头真醒目。", "战锤的轮廓真特别。"],
	"spellbook": ["书页的边缘真整齐。", "封面上的纹路很特别。", "这本书的轮廓真别致。"],
	"chest_large": ["这箱子真够大的。", "箱子比我还高呢。", "好大的箱子啊。"],
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
	var level := clampi(int(entry.get("level", 1)), 1, 10)
	var tier := 0 if level <= 3 else (1 if level <= 6 else 2)
	var index := posmod(variant, 3)
	var text: String = REACTIONS[category][index]
	var condition: String = ["值得多看几眼。", "常来看看，讲解也详细。", "馆里的明星藏品！"][tier]
	return text + "\n" + condition

static func empty_comment(variant: int = 0) -> String:
	return ["还在布展呀，\n期待新的发现。", "下次会展出什么呢？", "先逛一逛，\n等新展品上架。"][posmod(variant, 3)]
