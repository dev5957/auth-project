const {
  createChronique,
  listChroniques,
  getChroniqueById,
} = require('../services/chroniqueService');

async function create(req, res, next) {
  try {
    const chronique = await createChronique(req.user.userId, req.body);
    res.status(201).json({
      message: 'Chronique created',
      chronique,
    });
  } catch (err) {
    next(err);
  }
}

async function list(req, res, next) {
  try {
    const result = await listChroniques(req.user.userId, req.query);
    res.status(200).json(result);
  } catch (err) {
    next(err);
  }
}

async function getOne(req, res, next) {
  try {
    const chronique = await getChroniqueById(req.user.userId, req.params.id);
    res.status(200).json({ chronique });
  } catch (err) {
    next(err);
  }
}

module.exports = {
  create,
  list,
  getOne,
};
