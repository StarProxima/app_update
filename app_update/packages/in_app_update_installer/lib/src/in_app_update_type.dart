enum InAppUpdateType { immediate, flexible }

extension InAppUpdateTypeExtension on InAppUpdateType {
  bool get isImmediate => this == InAppUpdateType.immediate;
  bool get isFlexible => this == InAppUpdateType.flexible;

  InAppUpdateType get other =>
      this == InAppUpdateType.immediate
          ? InAppUpdateType.flexible
          : InAppUpdateType.immediate;
}
