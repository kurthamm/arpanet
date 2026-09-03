#include <stdio.h>
#include <errno.h>
#include <fcntl.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <getopt.h>
#include <signal.h>
#include "ncp.h"
#include <sys/wait.h>
#include "tty.h"

#define OLD_TELNET    1
#define NEW_TELNET   23

#define IAC   0377
#define DONT  0376
#define DO    0375
#define WONT  0374
#define WILL  0373
#define SB    0372
#define GA    0371
#define EL    0370
#define EC    0367
#define AYT   0366
#define AO    0365
#define IP    0364
#define BRK   0363
#define MARK  0362
#define NOP   0361
#define SE    0360
#define NUL   0000

#define OPT_BINARY              000
#define OPT_ECHO                001
#define OPT_RECONNECTION        002
#define OPT_SUPPRESS_GO_AHEAD   003
#define OPT_APPROX_MSG_SIZE     004
#define OPT_STATUS              005
#define OPT_TIMING_MARK         006
#define OPT_REMOTE_CTRL_TANDE   007
#define OPT_EXTENDED_ASCII      021
#define OPT_SUPDUP              025
#define OPT_SUPDUP_OUTPUT       026

#define OMARK         0200
#define OBREAK        0201
#define ONOP          0202
#define ONOECHO       0203
#define OECHO         0204
#define OHIDE         0205
#define OASCII        0240
#define OTRANSPARENT  0241
#define OEBCDIC       0242

static pid_t reader_pid = 0;
static pid_t writer_pid = 0;
static volatile sig_atomic_t terminate_requested = 0;

static int debug_mode = 0;
#define DEBUG_PRINTF(...) \
    do { if (debug_mode) fprintf(stderr, __VA_ARGS__); } while (0)

static void handle_term (int sig)
{
  (void)sig;
  terminate_requested = 1;
}

static const unsigned char old_client_options[] = {
  OECHO, NUL
};

static const unsigned char old_server_options[] = {
  ONOECHO, NUL
};

static const unsigned char new_client_options[] = {
  IAC, DO, OPT_ECHO,
  IAC, DO, OPT_SUPPRESS_GO_AHEAD,
  IAC, WILL, OPT_SUPPRESS_GO_AHEAD,
  NUL
};

static const unsigned char new_server_options[] = {
  IAC, DONT, OPT_ECHO,
  IAC, DO, OPT_SUPPRESS_GO_AHEAD,
  IAC, WILL, OPT_SUPPRESS_GO_AHEAD,
  IAC, WILL, OPT_ECHO,
  NUL
};

static const unsigned char bin_options[] = {
  NUL
};

static void option (int fd)
{
  unsigned char c;
  read (fd, &c, 1);
  switch (c) {
  case OPT_BINARY:
    break;
  case OPT_ECHO:
    break;
  case OPT_RECONNECTION:
    break;
  case OPT_SUPPRESS_GO_AHEAD:
    break;
  case OPT_APPROX_MSG_SIZE:
    break;
  case OPT_STATUS:
    break;
  case OPT_TIMING_MARK:
    break;
  case OPT_REMOTE_CTRL_TANDE:
    break;
  case OPT_EXTENDED_ASCII:
    break;
  case OPT_SUPDUP:
    break;
  case OPT_SUPDUP_OUTPUT:
    break;
  default:
    break;
  }
}

static void special (unsigned char c, int rfd, int wfd)
{
  switch (c) {
  case IAC:
    write (wfd, &c, 1);
    return;
  case DONT:
    option (rfd);
    return;
  case DO:
    option (rfd);
    return;
  case WONT:
    option (rfd);
    return;
  case WILL:
    option (rfd);
    return;
  case SB:
    return;
  case GA:
    return;
  case EL:
    return;
  case EC:
    write (wfd, "\b \b", 3);
    return;
  case AYT:
    return;
  case AO:
    return;
  case IP:
    return;
  case BRK:
    return;
  case MARK:
    return;
  case NOP:
    return;
  case SE:
    return;
  default:
    return;
  }
}

static void process_new (unsigned char data, int rfd, int wfd)
{
  switch (data) {
  case NUL:
    break;
  case IAC:
    read (rfd, &data, 1);
    special (data, rfd, wfd);
    break;
  default:
    write (wfd, &data, 1);
    break;
  }
}

static void process_old (unsigned char data, int rfd, int wfd)
{
  unsigned char crlf[] = { 015, 012 };
  switch (data) {
  case NUL:
    break;
  case 001: case 002: case 003: case 004: case 005: case 006:
    break;
  case 016: case 017: case 020: case 021: case 022: case 023:
  case 024: case 025: case 026: case 027: case 030: case 031:
  case 032:           case 034: case 035: case 036: case 037:
    break;
  case 0177:
    break;
  case 015:
    read (rfd, &data, 1);
    if (data == NUL)
      write (wfd, crlf, 1);
    else if (data == 012)
      write (wfd, crlf, 2);
    else
      fprintf (stderr, "[CR without LF or NUL]");
  case OMARK:
    break;
  case OBREAK:
    fprintf (stderr, "[BREAK]"); fflush (stderr);
    break;
  case ONOP:
    fprintf (stderr, "[NOP]"); fflush (stderr);
    break;
  case ONOECHO:
    fprintf (stderr, "[NOECHO]"); fflush (stderr);
    break;
  case OECHO:
    fprintf (stderr, "[ECHO]"); fflush (stderr);
    break;
  case OHIDE:
    fprintf (stderr, "[HIDE]"); fflush (stderr);
    break;
  case OASCII:
    fprintf (stderr, "[ASCII]"); fflush (stderr);
    break;
  case OTRANSPARENT:
    fprintf (stderr, "[TRANSPARENT]"); fflush (stderr);
    break;
  case OEBCDIC:
    fprintf (stderr, "[EBCDIC]"); fflush (stderr);
    break;
  default:
    write (wfd, &data, 1);
  }
}

static void process_bin (unsigned char data, int rfd, int wfd)
{
  write (wfd, &data, 1);
}


static int reader (int connection)
{
  unsigned char data[200];
  int fds[2];
  int size;
  ssize_t n = 0;
    if (pipe (fds) == -1)
      exit (1);
    fcntl (fds[0], F_SETFD, FD_CLOEXEC);
    fcntl (fds[1], F_SETFD, FD_CLOEXEC);
  reader_pid = fork();
  if (reader_pid) {
    close (fds[1]);
    return fds[0];
  }
  close (fds[0]);

  if (ncp_init (NULL) == -1)
    exit (1);

  for (;;) {
    size = sizeof data;
    if (ncp_read (connection, data, &size) == -1) {
      fprintf (stderr, "NCP read error.\n");
      exit (1);
    }
    if (size == 0)
      exit (0);
    n = write (fds[1], data, size);
    if (n <= 0) {
      if (n < 0 && errno == EPIPE) {
        DEBUG_PRINTF("DEBUG: reader child exiting cleanly on EPIPE.\n");
        exit (0);
      }
      DEBUG_PRINTF("DEBUG: reader child exiting on write error or EOF.\n");
      exit (1);
    }
  }
}

static int writer (int connection)
{
  unsigned char data[200], *ptr;
  ssize_t n, m;
  int fds[2];
  int size;

  if (pipe (fds) == -1)
    exit (1);
  fcntl (fds[0], F_SETFD, FD_CLOEXEC);
  fcntl (fds[1], F_SETFD, FD_CLOEXEC);

  writer_pid = fork();
  if (writer_pid) {
    close (fds[0]);
    return fds[1];
  }
  close (fds[1]);

  if (ncp_init (NULL) == -1)
    exit (1);

  for (;;) {
    n = read (fds[0], data, 200);
    if (n == 0)
      exit (0);
    if (n < 0)
      exit (1);
    ptr = data;
    for (ptr = data, m = n; m > 0; ptr += size, m -= size) {
      size = m;
      if (ncp_write (connection, ptr, &size) == -1) {
        fprintf (stderr, "NCP write error.\n");
        exit (1);
      }
      if (size == 0)
        exit (0);
    }
  }
}

static void telnet_client (int host, int sock,
                           void (*process) (unsigned char, int, int),
                           const unsigned char *options)
{
  int connection, byte_size;
  int reader_fd, writer_fd;
  size_t size;

  printf ("TELNET to host %03o.\n", host);

  byte_size = 8;
  switch (ncp_open (host, sock, &byte_size, &connection)) {
  case 0:
    break;
  case -1:
  default:
    fprintf (stderr, "NCP open error.\n");
    exit (1);
  case -2:
    fprintf (stderr, "Open refused.\n");
    exit (1);
  }

  reader_fd = reader (connection);
  writer_fd = writer (connection);

  size = strlen ((const char *)options);
  if (write (writer_fd, options, size) == -1) {
    fprintf (stderr, "write error.\n");
    exit (1);
  }

  tty_raw ();

  for (;;) {
    fd_set rfds;
    int n;
    FD_ZERO (&rfds);
    FD_SET (0, &rfds);
    FD_SET (reader_fd, &rfds);
    n = select (reader_fd + 1, &rfds, NULL, NULL, NULL);
    if (terminate_requested)
      goto end;
    if (n <= 0)
      break;

    if (FD_ISSET (0, &rfds)) {
      unsigned char data;
      if (read (0, &data, 1) <= 0)
        goto end;
      if (data == 035)
        goto quit;
      if (write (writer_fd, &data, 1) <= 0)
        goto end;
    }
    if (FD_ISSET (reader_fd, &rfds)) {
      unsigned char data;
      n = read (reader_fd, &data, 1);
      if (n == 1)
        process (data, reader_fd, 1);
      if (n <= 0)
        goto end;
    }
  }

 quit:
  printf ("TELNET> quit\r\n");
 end:
  DEBUG_PRINTF("DEBUG: client shutting down.\n");
  tty_restore ();

  DEBUG_PRINTF("DEBUG: signaling reader child (PID %d) to unblock from ncp_read.\n", reader_pid);
  kill (reader_pid, SIGTERM);

  DEBUG_PRINTF("DEBUG: closing pipes to children.\n");
  close (reader_fd);
  close (writer_fd);

  DEBUG_PRINTF("DEBUG: waiting for reader child (PID %d).\n", reader_pid);
  waitpid (reader_pid, NULL, 0);
  DEBUG_PRINTF("DEBUG: reader child reaped.\n");

  DEBUG_PRINTF("DEBUG: waiting for writer child (PID %d).\n", writer_pid);
  waitpid (writer_pid, NULL, 0);
  DEBUG_PRINTF("DEBUG: writer child reaped.\n");

  if (ncp_close (connection) == -1) {
    fprintf (stderr, "NCP close error.\n");
    exit (1);
  }
  DEBUG_PRINTF("DEBUG: client shutdown complete.\n");
}

static char **server_cmd;          /* set from argv after "--" */

static void serve_connection (int host, int connection,
                              void (*process) (unsigned char, int, int),
                              const unsigned char *options)
{
  int size;
  int reader_fd, writer_fd;
  pid_t shell_pid; // Declare shell_pid here
  int fd; // Declare fd here

  reader_fd = reader (connection);
  writer_fd = writer (connection);

  size = strlen ((const char *)options);
  if (write (writer_fd, options, size) == -1) {
    fprintf (stderr, "write error.\n");
    exit (1);
  }

  shell_pid = tty_run (server_cmd, &fd);

  int flags = fcntl (fd, F_GETFL);
  fcntl (fd, F_SETFL, flags | O_NONBLOCK);
  flags = fcntl (reader_fd, F_GETFL);
  fcntl (reader_fd, F_SETFL, flags | O_NONBLOCK);

  for (;;) {
    fd_set rfds;
    int n = fd > reader_fd ? fd : reader_fd;
    FD_ZERO (&rfds);
    FD_SET (fd, &rfds);
    FD_SET (reader_fd, &rfds);
    n = select (n + 1, &rfds, NULL, NULL, NULL);
    if (n <= 0)
      goto end;

    if (FD_ISSET (fd, &rfds)) {
      unsigned char data[200];
      ssize_t n = read (fd, data, sizeof data);
      if (n <= 0)
        goto end;
      data[n] = 0;
      write (writer_fd, data, n);
    }
    if (FD_ISSET (reader_fd, &rfds)) {
      unsigned char data;
      ssize_t n = read (reader_fd, &data, 1);
      if (n <= 0)
        goto end;
      process (data, reader_fd, fd);
    }
  }

 end:
  DEBUG_PRINTF("DEBUG: server shutting down.\n");

  DEBUG_PRINTF("DEBUG: closing pipes to children.\n");
  close (reader_fd);
  close (writer_fd);

  DEBUG_PRINTF("DEBUG: waiting for reader child (PID %d).\n", reader_pid);
  waitpid (reader_pid, NULL, 0);
  DEBUG_PRINTF("DEBUG: reader child reaped.\n");

  DEBUG_PRINTF("DEBUG: waiting for writer child (PID %d).\n", writer_pid);
  waitpid (writer_pid, NULL, 0);
  DEBUG_PRINTF("DEBUG: writer child reaped.\n");

  DEBUG_PRINTF("DEBUG: terminating shell process group (PID %d).\n", shell_pid);
  killpg (shell_pid, SIGHUP);
  waitpid (shell_pid, NULL, 0);
  DEBUG_PRINTF("DEBUG: shell process reaped.\n");

  if (ncp_close (connection) == -1) {
    fprintf (stderr, "NCP close error.\n");
    exit (1);
  }
  DEBUG_PRINTF("DEBUG: server shutdown complete.\n");
}

static void telnet_server (int host, int sock,
                           void (*process) (unsigned char, int, int),
                           const unsigned char *options)
{
  for (;;) {
    int connection, size;

    fprintf (stderr, "Listening to socket %d.\n", sock);

    size = 8;
    if (ncp_listen (sock, &size, &host, &connection) == -1) {
      fprintf (stderr, "NCP listen error.\n");
      exit (1);
    }

    pid_t pid = fork ();
    if (pid < 0) {
      perror ("fork");
      exit (1);
    }
    if (pid == 0) {
      /* Detach from the parent's session/process group. Without this,
         this child (and the reader()/writer() grandchildren it is about
         to fork, which inherit whatever session they're born into) stays
         in the same session as the long-lived listening parent and its
         controlling terminal (e.g. the pty screen(1) allocated for it).
         If that parent process exits for any reason while still the
         foreground process group of that terminal -- including hitting
         the existing "already listening" collision on its own repeat
         ncp_listen() call once a connection index it used is never freed
         -- the kernel sends SIGHUP to every other process left in that
         group. SIGHUP's default disposition is immediate termination
         (ncp_init() installs handlers for SIGINT/SIGTERM/SIGQUIT, not
         SIGHUP), which kills this connection's reader/writer/serve loop
         out from under an otherwise perfectly healthy session -- their
         NCP control sockets get closed without unlinking (bypassing
         atexit cleanup, same as SIGKILL would), which is exactly the
         "sendto ... Connection refused" signature seen once the daemon
         later tries to deliver their queued reply. setsid() makes this
         child its own session leader, so a sibling's or the parent's
         terminal-driven SIGHUP can never reach it.
       */
      if (setsid () == -1)
        perror ("setsid");

      /* The forked child inherited the parent's single NCP app-control
         socket (a connected AF_UNIX datagram fd created once in main()).
         If it kept using that fd, its own ncp_close() at teardown would
         race the parent's next ncp_listen() call on the very same fd:
         whichever process's recv() happens to unblock first steals
         whatever reply is pending, regardless of which of them it was
         meant for. reader()/writer() already avoid this by calling
         ncp_init() again right after their own fork(); do the same here
         so this child gets its own private socket (bound to a path keyed
         on its own, guaranteed-unique pid) before touching NCP at all. */
      if (ncp_init (NULL) == -1) {
        fprintf (stderr, "NCP re-init error in connection child.\n");
        exit (1);
      }
      serve_connection (host, connection, process, options);
      _exit (0);
    }

    /* parent: reap finished children without blocking, then go back to
       listening for the next visitor. */
    while (waitpid (-1, NULL, WNOHANG) > 0) ;
  }
}

static void usage (const char *argv0, int code)
{
  fprintf (stderr, "Usage: %s -c[bno] [-d] host\n"
           "or %s -s[bno] [-d] -- command [args]\n", argv0, argv0);
  if (code >= 0)
    exit (code);
}

int main (int argc, char **argv)
{
  void (*telnet) (int, int,
                  void (*) (unsigned char, int, int),
                  const unsigned char *) = NULL;
  void (*process) (unsigned char, int, int) = NULL;
  const unsigned char *client_options = NULL;
  const unsigned char *server_options = NULL;
  const unsigned char *options;
  int opt;
  int host = -1;
  int sock = -1;
  struct sigaction sa;

  memset (&sa, 0, sizeof sa);
  sa.sa_handler = handle_term;
  sigemptyset (&sa.sa_mask);
  sigaction (SIGTERM, &sa, NULL);
  sigaction (SIGINT, &sa, NULL);

  while ((opt = getopt (argc, argv, "bcnosp:d")) != -1) {
    switch (opt) {
    case 'b':
      if (process != NULL)
        usage (argv[0], 1);
      process = process_bin;
      client_options = bin_options;
      server_options = bin_options;
      break;
    case 'c':
      if (telnet != NULL)
        usage (argv[0], 1);
      telnet = telnet_client;
      break;
    case 'd':
      debug_mode = 1;
      break;
    case 'n':
      if (process != NULL)
        usage (argv[0], 1);
      process = process_new;
      client_options = new_client_options;
      server_options = new_server_options;
      if (sock == -1)
        sock = NEW_TELNET;
      break;
    case 'o':
      if (process != NULL)
        usage (argv[0], 1);
      process = process_old;
      client_options = old_client_options;
      server_options = old_server_options;
      if (sock == -1)
        sock = OLD_TELNET;
      break;
    case 'p':
      sock = atoi (optarg);
      break;
    case 's':
      if (telnet != NULL)
        usage (argv[0], 1);
      telnet = telnet_server;
      break;
    default:
      usage (argv[0], 1);
    }
  }

  /* These are the defaults. */
  if (sock == -1)
    sock = NEW_TELNET;
  if (process == NULL)
    process = process_new;
  if (telnet == NULL)
    telnet = telnet_client;
  if (client_options == NULL)
    client_options = new_client_options;
  if (server_options == NULL)
    server_options = new_server_options;

  if (telnet == telnet_client)
    host = atoi (argv[optind++]);

  if (telnet == telnet_server) {
    if (optind < 2 || strcmp (argv[optind - 1], "--") != 0 || optind >= argc) {
      fprintf (stderr, "%s: -s requires -- <command> [args]\n", argv[0]);
      exit (1);
    }
    server_cmd = &argv[optind];
  } else if (argc != optind) {
    usage(argv[0], 1);
  }

  if (ncp_init (NULL) == -1) {
    fprintf (stderr, "NCP initialization error: %s.\n", strerror (errno));
    if (errno == ECONNREFUSED)
      fprintf (stderr, "Is the NCP server started?\n");
    else if (errno == EFAULT)
      fprintf (stderr, "Is the NCP environment variable set?\n");
    exit (1);
  }
  sigaction (SIGTERM, &sa, NULL);
  sigaction (SIGINT, &sa, NULL);

  if (telnet == telnet_client)
    options = client_options;
  else
    options = server_options;
  telnet (host, sock, process, options);

  return 0;
}
