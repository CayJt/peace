import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../services/admin_api_service.dart';

class ChatsState extends Equatable {
  final bool loading, guardrailOnly;
  final String query;
  final List<Map<String, dynamic>> items;
  final int total, guardrailTotal, allTotal;
  final String? error;
  const ChatsState({
    this.loading = false,
    this.guardrailOnly = false,
    this.query = '',
    this.items = const [],
    this.total = 0,
    this.guardrailTotal = 0,
    this.allTotal = 0,
    this.error,
  });

  @override
  List<Object?> get props => [loading, guardrailOnly, query, items.length, total, guardrailTotal, allTotal, error];
}

class AdminChatsCubit extends Cubit<ChatsState> {
  AdminChatsCubit(this.api, {this.onUnauthorized}) : super(const ChatsState());
  final AdminApiService api;
  final void Function()? onUnauthorized;

  Future<void> load({bool? guardrailOnly, String? query}) async {
    final g = guardrailOnly ?? state.guardrailOnly, q = query ?? state.query;
    emit(ChatsState(loading: true, guardrailOnly: g, query: q, items: state.items));
    try {
      final j = await api.chatHistory(guardrailOnly: g, q: q);
      emit(ChatsState(
        guardrailOnly: g,
        query: q,
        items: (j['items'] as List).cast<Map<String, dynamic>>(),
        total: j['total'] as int,
        guardrailTotal: j['guardrail_total'] as int,
        allTotal: j['all_total'] as int,
      ));
    } on AdminApiException catch (err) {
      if (err.unauthorized) onUnauthorized?.call();
      emit(ChatsState(guardrailOnly: g, query: q, items: state.items, error: err.message));
    }
  }
}
