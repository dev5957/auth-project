require('dotenv').config();

const { assertAuthConfig } = require('./config/authConfig');

try {
  assertAuthConfig();
} catch (_) {
  process.exit(1);
}

const express = require('express');
const authRoutes = require('./routes/auth');
const chroniqueRoutes = require('./routes/chroniques');
const communityRoutes = require('./routes/communities');
const invitationRoutes = require('./routes/invitations');
const joinRequestRoutes = require('./routes/joinRequests');
const userRoutes = require('./routes/users');
const errorHandler = require('./middleware/errorHandler');
const { corsMiddleware } = require('./middleware/cors');
const { startChroniqueScheduler } = require('./services/chroniqueScheduler');

const app = express();
const PORT = process.env.PORT || 3000;

app.use(corsMiddleware);
app.use(express.json({ limit: '32kb' }));

app.get('/health', (req, res) => {
  res.json({
    status: 'ok',
    message: 'API is running',
  });
});

app.use('/auth', authRoutes);
app.use('/chroniques', chroniqueRoutes);
app.use('/communities', communityRoutes);
app.use('/invitations', invitationRoutes);
app.use('/join-requests', joinRequestRoutes);
app.use('/users', userRoutes);

app.use(errorHandler);

const server = app.listen(PORT, () => {
  console.log(`Server listening on port ${PORT}`);
  const scheduler = startChroniqueScheduler({ installSignals: false });
  if (!scheduler.enabled) {
    return;
  }
  const shutdown = () => {
    scheduler.stop();
    server.close(() => {
      process.exit(0);
    });
    setTimeout(() => process.exit(0), 3000).unref();
  };
  process.once('SIGTERM', shutdown);
  process.once('SIGINT', shutdown);
});
