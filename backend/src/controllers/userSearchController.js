const { searchUsers } = require('../services/userSearchService');

async function search(req, res, next) {
  try {
    const result = await searchUsers(req.query);
    res.status(200).json(result);
  } catch (err) {
    next(err);
  }
}

module.exports = {
  search,
};
