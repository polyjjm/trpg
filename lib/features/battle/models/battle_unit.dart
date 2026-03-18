class BattleUnit {
  final String name;
  final int maxHp;
  int hp;
  final int attack;

  BattleUnit({
    required this.name,
    required this.maxHp,
    required this.hp,
    required this.attack,
  });

  bool get isDead => hp <= 0;

  void takeDamage(int damage) {
    hp -= damage;
    if (hp < 0) hp = 0;
  }
}