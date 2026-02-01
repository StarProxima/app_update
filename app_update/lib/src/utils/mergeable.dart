// ignore_for_file: prefer-named-parameters

import '../models/update_rule/update_rule_config.dart';

abstract class Mergeable<T extends Mergeable<T>> {
  T merge(T other);

  static Map<String, dynamic>? mergeCustomParams(
    Map<String, dynamic>? customParams1,
    Map<String, dynamic>? customParams2, [
    Map<String, dynamic>? customParams3,
    Map<String, dynamic>? customParams4,
    Map<String, dynamic>? customParams5,
  ]) {
    final customParams = {
      ...?customParams1,
      ...?customParams2,
      ...?customParams3,
      ...?customParams4,
      ...?customParams5,
    };

    return customParams.isNotEmpty ? customParams : null;
  }

  static Map<K, T>? mergeMaps<K, T extends Mergeable<T>>(
    Map<K, T>? base,
    Map<K, T>? incoming,
  ) {
    if (base == null && incoming == null) return null;

    final merged = <K, T>{
      ...?base,
    };

    if (incoming != null) {
      for (final entry in incoming.entries) {
        final existing = merged[entry.key];
        if (existing == null) {
          merged[entry.key] = entry.value;
        } else {
          merged[entry.key] = existing.merge(entry.value);
        }
      }
    }

    return merged.isNotEmpty ? merged : null;
  }

  static List<UpdateRuleConfig<T>>? mergeRules<T extends Mergeable<T>>(
    List<UpdateRuleConfig<T>>? rules1,
    List<UpdateRuleConfig<T>>? rules2, [
    List<UpdateRuleConfig<T>>? rules3,
    List<UpdateRuleConfig<T>>? rules4,
    List<UpdateRuleConfig<T>>? rules5,
  ]) {
    final rules = [
      ...?rules1,
      ...?rules2,
      ...?rules3,
      ...?rules4,
      ...?rules5,
    ];

    return rules.isNotEmpty ? rules : null;
  }
}
