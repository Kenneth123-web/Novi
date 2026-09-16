"""Chinese search aliases for MediaCrawler platforms.

Bilibili and the other MediaCrawler sources index Chinese much more densely
than English. Matching the English catalog name against a 导数 video would
drop almost every hit, so each concept we search for has the name a Chinese
student would type.
"""

from __future__ import annotations

# concept slug -> search terms used on Chinese platforms (MediaCrawler / Bilibili).
ZH_QUERIES: dict[str, list[str]] = {
    "limits": ["极限 微积分 讲解"],
    "derivatives": ["导数 讲解 高中"],
    "chain-rule": ["链式法则 导数"],
    "integrals": ["积分 讲解"],
    "differential-equations": ["微分方程 入门"],
    "linear-equations": ["一元一次方程 讲解"],
    "quadratic-equations": ["二次方程 讲解"],
    "functions": ["函数 高中数学"],
    "trigonometric-ratios": ["三角函数 讲解"],
    "exponentials-logarithms": ["指数对数 讲解"],
    "probability": ["概率 讲解"],
    "bayes-theorem": ["贝叶斯定理 讲解"],
    "vectors": ["向量 讲解"],
    "matrices": ["矩阵 讲解"],
    "newtons-laws": ["牛顿定律 讲解"],
    "kinematics": ["运动学 讲解"],
    "ohms-law": ["欧姆定律 讲解"],
    "work-energy": ["动能定理 讲解"],
    "waves": ["机械波 讲解"],
    "optics": ["光学 讲解"],
    "entropy": ["熵 热力学"],
    "special-relativity": ["狭义相对论 讲解"],
    "photosynthesis": ["光合作用 讲解"],
    "cellular-respiration": ["细胞呼吸 讲解"],
    "dna-replication": ["DNA复制 讲解"],
    "natural-selection": ["自然选择 讲解"],
    "cell-structure": ["细胞结构 讲解"],
    "atomic-structure": ["原子结构 讲解"],
    "chemical-bonding": ["化学键 讲解"],
    "acids-bases": ["酸碱 讲解"],
    "equilibrium": ["化学平衡 讲解"],
    "big-o": ["时间复杂度 算法"],
    "recursion": ["递归 算法 讲解"],
    "dynamic-programming": ["动态规划 讲解"],
    "neural-networks": ["神经网络 入门"],
    "backpropagation": ["反向传播 讲解"],
    "supply-demand": ["供求 经济学"],
    "inflation": ["通货膨胀 讲解"],
    "cognitive-biases": ["认知偏差 讲解"],
    "climate-change": ["气候变化 讲解"],
    "close-reading": ["文本细读"],
}


def queries_for(slug: str, name: str) -> list[str]:
    return ZH_QUERIES.get(slug) or [f"{name} 教程"]
