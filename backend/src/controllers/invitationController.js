const {
  createInvitation,
  listReceivedInvitations,
  acceptInvitation,
  declineInvitation,
  cancelInvitation,
} = require('../services/invitationService');

async function create(req, res, next) {
  try {
    const invitation = await createInvitation(
      req.user.userId,
      req.params.id,
      req.body
    );
    res.status(201).json({
      message: 'Invitation created',
      invitation,
    });
  } catch (err) {
    next(err);
  }
}

async function listReceived(req, res, next) {
  try {
    const result = await listReceivedInvitations(req.user.userId);
    res.status(200).json(result);
  } catch (err) {
    next(err);
  }
}

async function accept(req, res, next) {
  try {
    const result = await acceptInvitation(req.user.userId, req.params.id);
    res.status(200).json(result);
  } catch (err) {
    next(err);
  }
}

async function decline(req, res, next) {
  try {
    const invitation = await declineInvitation(req.user.userId, req.params.id);
    res.status(200).json({ invitation });
  } catch (err) {
    next(err);
  }
}

async function cancel(req, res, next) {
  try {
    const invitation = await cancelInvitation(req.user.userId, req.params.id);
    res.status(200).json({ invitation });
  } catch (err) {
    next(err);
  }
}

module.exports = {
  create,
  listReceived,
  accept,
  decline,
  cancel,
};
