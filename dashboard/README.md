# 🎮 MojoRust Trading Dashboard

Real-time web dashboard for monitoring and controlling the MojoRust algorithmic trading bot.

## Features

### 📊 **Real-time Monitoring**
- Live portfolio value and P&L tracking
- Trading status and performance metrics
- Position monitoring with unrealized/realized P&L
- Risk metrics and alerts
- Strategy performance comparison

### 🎛️ **Trading Controls**
- Start/Stop/Pause/Resume trading
- Strategy switching with one click
- Manual trade execution
- Risk limit adjustments
- Emergency stop functionality

### 🎯 **Manual Targeting**
- Add token addresses to watchlist
- Configure individual token parameters
- Set priority levels and expiration
- Monitor multiple tokens simultaneously
- Execute manual trades on watched tokens

### 📈 **Analytics**
- Historical performance charts
- Trade execution analysis
- Risk metrics visualization
- Strategy comparison
- Win rate and ROI tracking

### 🔔 **Alerts & Notifications**
- Real-time risk alerts
- Trade execution notifications
- System health monitoring
- Custom alert thresholds

## Technology Stack

- **Frontend**: React 18 + TypeScript
- **Real-time Communication**: WebSocket
- **API Integration**: FastAPI backend
- **Charts**: Chart.js / Recharts
- **UI Components**: Material-UI / Ant Design
- **State Management**: Redux Toolkit / Zustand

## Quick Start

### Prerequisites
- Node.js 16+
- npm or yarn
- Trading Control API running on port 8083

### Installation

```bash
# Clone the repository
git clone <repository-url>
cd MojoRust/dashboard

# Install dependencies
npm install

# Start development server
npm start
```

The dashboard will be available at `http://localhost:3000`

### Configuration

Create a `.env` file:

```env
REACT_APP_API_URL=http://localhost:8083
REACT_APP_WS_URL=ws://localhost:8083
REACT_APP_REFRESH_INTERVAL=5000
```

## Dashboard Sections

### 1. **Overview Panel**
- Current trading status
- Portfolio value and daily P&L
- Active strategy
- System health indicators

### 2. **Trading Controls**
- Start/Stop/Pause buttons
- Strategy selector
- Risk limit sliders
- Emergency stop button

### 3. **Portfolio View**
- Position list with details
- Real-time P&L updates
- Position size controls
- Close position buttons

### 4. **Manual Targeting**
- Add token form
- Watchlist management
- Token analysis cards
- Manual trade buttons

### 5. **Risk Management**
- Risk metrics display
- Alert history
- Risk limit configuration
- Intervention history

### 6. **Performance Analytics**
- P&L charts
- Win rate statistics
- Strategy comparison
- Trade history

## API Integration

The dashboard integrates with the Trading Control API through:

### REST API Endpoints
- `GET /api/trading/status` - Current trading status
- `POST /api/trading/start` - Start trading
- `POST /api/trading/stop` - Stop trading
- `POST /api/trading/pause` - Pause trading
- `POST /api/trading/resume` - Resume trading
- `POST /api/trading/emergency/stop` - Emergency stop
- `GET /api/targeting/watchlist` - Get token watchlist
- `POST /api/targeting/add` - Add token to watchlist
- `POST /api/trading/manual/execute` - Execute manual trade

### WebSocket Events
- `status_update` - Real-time trading status
- `portfolio_update` - Portfolio value changes
- `trade_executed` - New trade execution
- `risk_alert` - Risk management alerts
- `strategy_changed` - Strategy switch notifications

## Security Considerations

- API authentication using JWT tokens
- HTTPS communication in production
- Rate limiting on API calls
- Input validation and sanitization
- Secure WebSocket connections (WSS)

## Development

### Project Structure
```
dashboard/
├── src/
│   ├── components/          # React components
│   ├── pages/              # Page components
│   ├── hooks/              # Custom React hooks
│   ├── services/           # API service layer
│   ├── utils/              # Utility functions
│   ├── types/              # TypeScript type definitions
│   └── styles/             # CSS/styling files
├── public/                 # Static assets
└── package.json
```

### Adding New Features

1. **Component Creation**: Create new component in `src/components/`
2. **API Integration**: Add API service in `src/services/`
3. **Type Definitions**: Define types in `src/types/`
4. **Styling**: Add styles in `src/styles/`
5. **Testing**: Write unit tests for components

### State Management

Using React Context + useReducer for local state:
```typescript
// Trading state context
const TradingContext = createContext<TradingState>();

// Reducer for state updates
const tradingReducer = (state: TradingState, action: TradingAction) => {
  // Handle actions
};
```

### WebSocket Integration

Custom hook for WebSocket management:
```typescript
const useTradingWebSocket = () => {
  const [socket, setSocket] = useState<WebSocket | null>(null);
  const [lastMessage, setLastMessage] = useState<any>(null);

  // WebSocket connection and message handling
};
```

## Deployment

### Production Build
```bash
npm run build
```

### Docker Deployment
```dockerfile
FROM node:16-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production
COPY . .
RUN npm run build
EXPOSE 3000
CMD ["npm", "start"]
```

### Environment Variables for Production
```env
REACT_APP_API_URL=https://your-api-domain.com
REACT_APP_WS_URL=wss://your-api-domain.com
REACT_APP_ENVIRONMENT=production
```

## Troubleshooting

### Common Issues

1. **WebSocket Connection Failed**
   - Check if the API server is running on the correct port
   - Verify WebSocket URL configuration
   - Check firewall settings

2. **API Errors**
   - Verify API URL in environment variables
   - Check API server logs
   - Ensure proper authentication

3. **Performance Issues**
   - Optimize re-renders with React.memo
   - Implement virtual scrolling for large lists
   - Use pagination for historical data

### Debug Mode

Enable debug logging:
```env
REACT_APP_DEBUG=true
```

## Contributing

1. Follow the existing code style
2. Write tests for new features
3. Update documentation
4. Submit pull requests with clear descriptions

## License

This dashboard is part of the MojoRust trading bot project.