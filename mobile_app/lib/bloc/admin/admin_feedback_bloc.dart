import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../services/admin_api_service.dart';

abstract class FeedbackEvent extends Equatable {
  const FeedbackEvent();
  @override
  List<Object?> get props => [];
}

class FeedbackLoaded extends FeedbackEvent {
  const FeedbackLoaded();
}

class FeedbackStatusChanged extends FeedbackEvent {
  final int id;
  final String status;
  const FeedbackStatusChanged(this.id, this.status);
  @override
  List<Object?> get props => [id, status];
}

class FeedbackNotesSaved extends FeedbackEvent {
  final int id;
  final String notes;
  const FeedbackNotesSaved(this.id, this.notes);
  @override
  List<Object?> get props => [id, notes];
}

class FeedbackState extends Equatable {
  final bool loading;
  final List<FeedbackItem> items;
  final Map<String, int> counts;
  final String? error;
  const FeedbackState({this.loading = false, this.items = const [], this.counts = const {}, this.error});

  List<FeedbackItem> byStatus(String s) => items.where((i) => i.status == s).toList();

  @override
  List<Object?> get props => [loading, items.map((i) => (i.id, i.status, i.adminNotes)).toList(), counts, error];
}

class AdminFeedbackBloc extends Bloc<FeedbackEvent, FeedbackState> {
  AdminFeedbackBloc(this.api, {this.onUnauthorized}) : super(const FeedbackState()) {
    on<FeedbackLoaded>((e, emit) async {
      emit(FeedbackState(loading: true, items: state.items, counts: state.counts));
      await _load(emit);
    });
    on<FeedbackStatusChanged>((e, emit) => _patch(emit, e.id, status: e.status));
    on<FeedbackNotesSaved>((e, emit) => _patch(emit, e.id, notes: e.notes));
  }

  final AdminApiService api;
  final void Function()? onUnauthorized;

  Future<void> _load(Emitter<FeedbackState> emit) async {
    try {
      final r = await api.feedback();
      emit(FeedbackState(items: r.items, counts: r.counts));
    } on AdminApiException catch (err) {
      if (err.unauthorized) onUnauthorized?.call();
      emit(FeedbackState(items: state.items, counts: state.counts, error: err.message));
    }
  }

  Future<void> _patch(Emitter<FeedbackState> emit, int id, {String? status, String? notes}) async {
    try {
      await api.patchFeedback(id, status: status, notes: notes);
      await _load(emit); // counts come from the server so they never drift
    } on AdminApiException catch (err) {
      if (err.unauthorized) onUnauthorized?.call();
      emit(FeedbackState(items: state.items, counts: state.counts, error: err.message));
    }
  }
}
