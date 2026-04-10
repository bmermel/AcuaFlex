/// Estado de una entrega.
enum DeliveryState {
  pendiente,
  entregado,
  noEntregado,
}

extension DeliveryStateX on DeliveryState {
  String get label {
    switch (this) {
      case DeliveryState.pendiente:
        return 'Pendiente';
      case DeliveryState.entregado:
        return 'Entregado';
      case DeliveryState.noEntregado:
        return 'No entregado';
    }
  }
}
