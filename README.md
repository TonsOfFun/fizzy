# Fizzy

This is the source code of [Fizzy](https://fizzy.do/), the Kanban tracking tool for issues and ideas by [37signals](https://37signals.com).

## Deploying Fizzy

If you'd like to run Fizzy on your own server, we recommend deploying it with [Kamal](https://kamal-deploy.org/).
Kamal makes it easier to set up a bare server, copy the application to it, and manage the configuration settings that it uses.

(Kamal is also what we use to deploy Fizzy at 37signals. If you're curious about what our deployment configuration looks like, you can find it inside [`fizzy-saas`](https://github.com/basecamp/fizzy-saas).)

This repo contains a starter deployment file that you can modify for your own specific use. That file lives at [config/deploy.yml](config/deploy.yml), which is the default place where Kamal will look for it.

The steps to configure your very own Fizzy are:

1. Fork the repo
2. Edit few things in config/deploy.yml and .kamal/secrets
3. Run `kamal setup` to do your first deploy.

We'll go through each of these in turn.

### Fork the repo

To make it easy to customise Fizzy's settings for your own instance, you should start by creating your own GitHub fork of the repo.
That allows you to commit your changes, and track them over time.
You can always re-sync your fork to pick up new changes from the main repo over time.

Once you've got your fork ready, run `bin/setup` from within it, to make sure everything is installed.

### Editing the configuration

The config/deploy.yml has been mostly set up for you, but you'll need to fill out some sections that are specific to your instance.
To get started, the parts you need to change are all in the "About your deployment" section.
We've added comments to that file to highlight what each setting needs to be, but the main ones are:

- `servers/web`: Enter the hostname of the server you're deploying to here. This should be an address that you can access via `ssh`.
- `ssh/user`: If you access your server a `root` you can leave this alone; if you use a different user, set it here.
- `proxy/ssl` and `proxy/host`: Kamal can set up SSL certificates for you automatically. To enable that, set the hostname again as `host`. If you don't want SSL for some reason, you can set `ssl: false` to turn it off.
- `env/clear/MAILER_FROM_ADDRESS`: This is the email address that Fizzy will send emails from. It should usually be an address from the same domain where you're running Fizzy.
- `env/clear/SMTP_ADDRESS`: The address of an SMTP server that you can send email through. You can use a 3rd-party service for this, like Sendgrid or Postmark, in which case their documentation will tell you what to use for this.
- `env/clear/MULTI_TENANT`: Set to `false` to enable single-tenant mode (disable multi-account signups).


Fizzy also requires a few environment variables to be set up, some of which contain secrets.
The simplest way to do this is to put them in a file called `.kamal/secrets`.
Because this file will contain secret credentials, it's important that you DON'T CHECK THIS FILE INTO YOUR REPO! You can add the filename to `.gitignore` to ensure you don't commit this file accidentally.

If you use a password manager like 1Password, you can also opt to keep your secrets there instead.
Refer to the [Kamal documentation](https://kamal-deploy.org/docs/configuration/environment-variables/#secrets) for more information about how to do that.

To store your secrets, create the file `.kamal/secrets` and enter something like the following:

```ini
SECRET_KEY_BASE=12345
VAPID_PUBLIC_KEY=something
VAPID_PRIVATE_KEY=somethingelse
SMTP_USERNAME=email-provider-username
SMTP_PASSWORD=email-provider-password
```

The values you enter here will be specific to you, and you can get or create them as follows:

- `SECRET_KEY_BASE` should be a long, random secret. You can run `bin/rails secret` to create a suitable value for this.
- `SMTP_USERNAME` & `SMTP_PASSWORD` should be valid credentials for your SMTP server. If you're using a 3rd-party service here, consult their documentation for what to use.
- `VAPID_PUBLIC_KEY` & `VAPID_PRIVATE_KEY` are a pair of credentials that are used for sending notifications. You can create your own keys by starting a development console with:

  ```sh
  bin/rails c
  ```

  And then run the following to create a new pair of keys:

  ```ruby
  vapid_key = WebPush.generate_key

  puts "VAPID_PRIVATE_KEY=#{vapid_key.private_key}"
  puts "VAPID_PUBLIC_KEY=#{vapid_key.public_key}"
  ```

Once you've made all those changes, commit them to your fork so they're saved.

### Deploy Fizzy!

You can now do your first deploy by running:

```sh
bin/kamal setup
```

This will set up Docker (if needed), build your Fizzy app container, configure it, and start it running.

After the first deploy is done, any subsequent steps won't need to do that initial setup. So for future deploys you can just run:

```sh
bin/kamal deploy
```

## File storage (Active Storage)

Production uses the local disk service by default. To use any other service defined in `config/storage.yml`, set `ACTIVE_STORAGE_SERVICE`.

To use the included `s3` service, set:

- `ACTIVE_STORAGE_SERVICE=s3`
- `S3_ACCESS_KEY_ID`
- `S3_BUCKET` (defaults to `fizzy-#{Rails.env}-activestorage`)
- `S3_REGION` (defaults to `us-east-1`)
- `S3_SECRET_ACCESS_KEY`

Optional for S3-compatible endpoints:

- `S3_ENDPOINT`
- `S3_FORCE_PATH_STYLE=true`
- `S3_REQUEST_CHECKSUM_CALCULATION` (defaults to `when_supported`)
- `S3_RESPONSE_CHECKSUM_VALIDATION` (defaults to `when_supported`)

## Development

### Setting up

First, get everything installed and configured with:

```sh
bin/setup
bin/setup --reset # Reset the database and seed it
```

And then run the development server:

```sh
bin/dev
```

You'll be able to access the app in development at http://fizzy.localhost:3006.

To login, enter `david@example.com` and grab the verification code from the browser console to sign in.

### Web Push Notifications

Fizzy uses VAPID (Voluntary Application Server Identification) keys to send browser push notifications. For notifications to work in development you'll need to generate a key pair and set these environment variables:

- `VAPID_PRIVATE_KEY`
- `VAPID_PUBLIC_KEY`

Generate them with the `web-push` gem:

```ruby
vapid_key = WebPush.generate_key

puts "VAPID_PRIVATE_KEY=#{vapid_key.private_key}"
puts "VAPID_PUBLIC_KEY=#{vapid_key.public_key}"
```

### Running tests

For fast feedback loops, unit tests can be run with:

```sh
bin/rails test
```

The full continuous integration tests can be run with:

```sh
bin/ci
```

### Database configuration

Fizzy works with SQLite by default and supports MySQL too. You can switch adapters with the `DATABASE_ADAPTER` environment variable. For example, to develop locally against MySQL:

```sh
DATABASE_ADAPTER=mysql bin/setup --reset
DATABASE_ADAPTER=mysql bin/ci
```

The remote CI pipeline will run tests against both SQLite and MySQL.

### Outbound Emails

You can view email previews at http://fizzy.localhost:3006/rails/mailers.

You can enable or disable [`letter_opener`](https://github.com/ryanb/letter_opener) to open sent emails automatically with:

```sh
bin/rails dev:email
```

Under the hood, this will create or remove `tmp/email-dev.txt`.

## SaaS gem

37signals bundles Fizzy with [`fizzy-saas`](https://github.com/basecamp/fizzy-saas), a companion gem that links Fizzy with our billing system and contains our production setup.

This gem depends on some private git repositories and it is not meant to be used by third parties. But we hope it can serve as inspiration for anyone wanting to run fizzy on their own infrastructure.

## AI Agents (ActiveAgent Integration)

This fork includes AI-powered features built with [ActiveAgent](https://github.com/activeagents/activeagent) and [SolidAgent](https://github.com/activeagents/solid_agent). These provide in-app AI assistance for writing, research, and file analysis.

### Available Agents

| Agent | Description | Actions |
|-------|-------------|---------|
| **WritingAssistantAgent** | Helps improve card content | `improve`, `summarize`, `expand`, `adjust_tone` |
| **ResearchAgent** | Web search and URL fetching | `research`, `suggest_topics`, `break_down_task` |
| **FileAnalysisAgent** | Image/document analysis with GPT-4o vision | `analyze`, `extract_text`, `describe_image` |

### Configuration

AI features require an OpenAI API key. Set the following environment variable:

```bash
OPENAI_API_KEY=your-api-key
```

For web search functionality, the ResearchAgent uses DuckDuckGo by default, but this can be rate-limited. For more reliable search, configure the Brave Search API (free tier available at https://brave.com/search/api/):

```bash
BRAVE_SEARCH_API_KEY=your-brave-api-key
```

Provider configuration is in `config/active_agent.yml`.

### Architecture

Agents follow Rails conventions with an MVC-like pattern:

```
app/
├── agents/
│   ├── application_agent.rb      # Base class with shared concerns
│   ├── writing_assistant_agent.rb
│   ├── research_agent.rb
│   └── file_analysis_agent.rb
└── views/
    ├── research_agent/
    │   ├── instructions.text.erb  # System prompt
    │   ├── research.text.erb      # Action template
    │   └── tools/                 # Tool schemas (JSON)
    │       ├── web_search.json.erb
    │       └── web_fetch.json.erb
    └── writing_assistant_agent/
        └── ...
```

Key concepts:
- **`generate_with`**: Configures the LLM provider and model
- **`has_tools`**: Declares available tools (loaded from JSON templates or inline)
- **`has_context`**: Enables context persistence for audit trails
- **`on_stream`**: Broadcasts chunks via ActionCable for real-time UI updates

### Adding a New Agent

1. Create the agent class in `app/agents/`:

```ruby
class MyAgent < ApplicationAgent
  has_context
  has_tools :my_tool

  generate_with :openai, model: "gpt-4o", stream: true

  on_stream :broadcast_chunk
  on_stream_close :broadcast_complete

  def my_action
    @input = params[:input]
    create_context(contextable: params[:contextable], input_params: { input: @input })
    prompt tools: tools, tool_choice: "auto"
  end

  def my_tool(arg:)
    # Tool implementation
    "Result for #{arg}"
  end

  private

  def broadcast_chunk(chunk)
    return unless chunk.message && params[:stream_id]
    ActionCable.server.broadcast(params[:stream_id], { content: chunk.message[:content] })
  end

  def broadcast_complete(chunk)
    return unless params[:stream_id]
    ActionCable.server.broadcast(params[:stream_id], { done: true })
  end
end
```

2. Create view templates in `app/views/my_agent/`:
   - `instructions.text.erb` - System prompt
   - `my_action.text.erb` - User message template
   - `tools/my_tool.json.erb` - Tool schema (OpenAI format)

3. Wire up the controller and routes as needed.

## Contributing

We welcome contributions! Please read our [style guide](STYLE.md) before submitting code.

## License

Fizzy is released under the [O'Saasy License](LICENSE.md).
