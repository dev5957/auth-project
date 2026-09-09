require('dotenv').config();

const { assertAuthConfig } = require('./config/authConfig');

try {
  assertAuthConfig();
} catch (_) {
  process.exit(1);
}

const express = require('express');
const authRoutes = require('./routes/auth');
const errorHandler = require('./middleware/errorHandler');

const app = express();
const PORT = process.env.PORT || 3000;

app.use(express.json({ limit: '32kb' }));

app.get('/health', (req, res) => {
  res.json({
    status: 'ok',
    message: 'API is running',
  });
});

app.use('/auth', authRoutes);

app.use(errorHandler);

app.listen(PORT, () => {
  console.log(`Server listening on port ${PORT}`);
});
