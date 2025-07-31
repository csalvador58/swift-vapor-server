# SwiftVaporServer

## Getting Started

Setup local development env
```bash
cp env.example .env.development
```

Run migrations (Only if ENV_MODE is not set to DEBUG)
```bash
swift run SwiftVaporServer migrate --yes
```

Start server
```bash
swift run SwiftVaporServer serve
```

Run tests
```bash
swift test
```