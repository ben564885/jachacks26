FROM python:3.12-slim

WORKDIR /app

# jac-scale is not optional here. Without it `jac start` still serves walkers,
# but @restspec does not exist -- which means notchsocket.jac's
# @restspec(protocol=APIProtocol.WEBSOCKET) route is simply absent from the
# deployed image, along with /docs, /healthz, the /graph visualizer and the
# admin portal. `requests` is a transitive import of the plugin that its own
# metadata does not declare; without it the plugin fails to load quietly and
# you get the stripped-down server back with no error at the call site.
# `jac plugins` shows whether jac-scale:scale actually loaded.
RUN pip install --no-cache-dir \
      "jaclang==0.16.7" \
      "jac-scale==0.2.31" \
      "byllm==0.6.19" \
      "requests>=2.31.0"

COPY . .

EXPOSE 8080

# `jac start` shuts down when stdin closes. In a container that is not
# hypothetical: the server drained and exited 0 about five minutes into a run,
# and the machine then sat stopped until the next request woke it -- losing the
# graph with it. Holding stdin open with a pipe that never delivers EOF is what
# keeps it running.
CMD ["sh", "-c", "sleep infinity | jac start main.jac --port 8080 --no_client"]
