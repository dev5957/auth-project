const express = require('express');
const {
  create,
  list,
  getOne,
  update,
  archive,
  restore,
  remove,
  createUpload,
  completeUpload,
  removeMedia,
  reorder,
} = require('../controllers/chroniqueController');
const { requireAuth } = require('../middleware/authMiddleware');
const { createRateLimiter } = require('../middleware/rateLimit');

const FIFTEEN_MINUTES_MS = 15 * 60 * 1000;

const chroniqueRateLimit = {
  write: createRateLimiter({ windowMs: FIFTEEN_MINUTES_MS, max: 30 }),
  read: createRateLimiter({ windowMs: FIFTEEN_MINUTES_MS, max: 60 }),
};

const router = express.Router();

router.use(requireAuth);

router.post('/', chroniqueRateLimit.write, create);
router.get('/', chroniqueRateLimit.read, list);
router.post('/:id/archive', chroniqueRateLimit.write, archive);
router.post('/:id/restore', chroniqueRateLimit.write, restore);
router.post('/:id/media/uploads', chroniqueRateLimit.write, createUpload);
router.post('/:id/media/:mediaId/complete', chroniqueRateLimit.write, completeUpload);
router.patch('/:id/media/order', chroniqueRateLimit.write, reorder);
router.delete('/:id/media/:mediaId', chroniqueRateLimit.write, removeMedia);
router.patch('/:id', chroniqueRateLimit.write, update);
router.get('/:id', chroniqueRateLimit.read, getOne);
router.delete('/:id', chroniqueRateLimit.write, remove);

module.exports = router;
