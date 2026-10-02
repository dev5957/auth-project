import '../../../core/network/api_exception.dart';

abstract final class InvitationMessages {
  static const selectedHint =
      'Vérifiez l’utilisateur sélectionné, puis envoyez l’invitation.';
  static const sent = 'Invitation envoyée. Elle est en attente de réponse.';
  static const accepted = 'Vous avez rejoint la communauté.';
  static const declined = 'Invitation refusée.';
  static const unavailable = 'Cette invitation n’est plus disponible.';
  static const emptyInbox = 'Aucune invitation en attente';
  static const sentSectionTitle = 'Invitations envoyées';
  static const sentEmpty = 'Aucune invitation envoyée';
  static const statusPending = 'En attente';
  static const statusDeclined = 'Refusée';
  static const statusAccepted = 'Acceptée';
  static const genericRetry = 'Impossible de terminer l’action. Réessayez.';
  static const unknown = 'Une erreur est survenue. Veuillez réessayer.';

  static String fromApi(ApiException error) {
    if (error.statusCode == 401) {
      return 'Session expirée';
    }
    switch (error.message) {
      case 'Community not found':
        return 'Communauté introuvable';
      case 'User not found':
        return 'Utilisateur introuvable';
      case 'cannot invite yourself':
        return 'Impossible de s’inviter soi-même.';
      case 'user is already a member':
        return 'Cet utilisateur est déjà membre.';
      case 'invitation limit reached':
        return 'Cet utilisateur a déjà refusé cinq invitations. Invitation impossible pour le moment.';
      case 'invitation cannot be sent':
        return 'Invitation impossible à envoyer pour le moment.';
      case 'invitation is not pending':
        return 'Cette invitation a déjà été traitée.';
      case 'Invitation not found':
        return unavailable;
      case 'Network error':
        return genericRetry;
      default:
        return unknown;
    }
  }

  static String sentStatusLabel(String status) {
    switch (status) {
      case 'pending':
        return statusPending;
      case 'declined':
        return statusDeclined;
      case 'accepted':
        return statusAccepted;
      default:
        return unknown;
    }
  }
}
