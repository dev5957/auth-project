const express = require('express');

const app = express();
const PORT = process.env.PORT || 3000;

app.get('/health', (req, res) => {
  res.json({
    status: 'ok',
    message: 'API is running',
  });
});

app.listen(PORT, () => {
  console.log(`Server listening on port ${PORT}`);
});
