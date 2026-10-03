import '../../../core/network/api_exception.dart';

abstract final class JoinRequestMessages {
  static const askToJoin = 'Demander à rejoindre';
  static const pending = 'Demande en attente';
  static const accepted = 'Acceptée';
  static const declined = 'Refusée';
  static const cancelled = 'Annulée';
  static const mineTitle = 'Mes demandes';
  static const mineEmpty = 'Aucune demande pour le moment';
  static const ownerTitle = 'Demandes d’adhésion';
  static const ownerPendingTitle = 'En attente';
  static const ownerHistoryTitle = 'Historique';
  static const ownerPendingEmpty = 'Aucune demande en attente';
  static const ownerHistoryEmpty = 'Aucun historique';
  static const accept = 'Accepter';
  static const decline = 'Refuser';
  static const acceptedNotice = 'Demande acceptée.';
  static const declinedNotice = 'Demande refusée.';
  static const alreadyMember = 'Vous êtes déjà membre de cette communauté.';
  static const alreadyPending = pending;
  static const treated = 'Cette demande a déjà été traitée.';
  static const unavailable = 'Cette demande n’est plus disponible.';
  static const genericRetry = 'Impossible de terminer l’action. Réessayez.';
  static const unknown = 'Une erreur est survenue. Veuillez réessayer.';

  static String fromApi(ApiException error) {
    if (error.statusCode == 401) {
      return 'Session expirée';
    }
    switch (error.message) {
      case 'Community not found':
        return 'Communauté introuvable';
      case 'Join request not found':
        return unavailable;
      case 'user is already a member':
        return alreadyMember;
      case 'join request already pending':
        return alreadyPending;
      case 'join request is not pending':
        return treated;
      case 'Network error':
        return genericRetry;
      default:
        return unknown;
    }
  }

  static String mineStatusLabel(String status) {
    switch (status) {
      case 'pending':
        return pending;
      case 'accepted':
        return accepted;
      case 'declined':
        return declined;
      case 'cancelled':
        return cancelled;
      default:
        return unknown;
    }
  }

  static String ownerStatusLabel(String status) {
    switch (status) {
      case 'pending':
        return pending;
      case 'accepted':
        return accepted;
      case 'declined':
        return declined;
      default:
        return unknown;
    }
  }
}
