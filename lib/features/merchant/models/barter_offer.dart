/// 상인에게 giveItemId를 건네면 receiveItemId를 받는 물물교환 한 건.
class BarterOffer {
  final String giveItemId;
  final String receiveItemId;

  const BarterOffer({
    required this.giveItemId,
    required this.receiveItemId,
  });
}
