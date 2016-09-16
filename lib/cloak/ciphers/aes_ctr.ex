defmodule Cloak.AES.CTR do
  @moduledoc """
  A `Cloak.Cipher` which encrypts values with the AES cipher in CTR (stream) mode.

  ## Configuration

  In addition to the normal `:default` and `:tag` configuration options, this
  cipher takes a `:keys` option to support using multiple AES keys at the same
  time.

      config :cloak, Cloak.AES.CTR,
        default: true,
        tag: "AES",
        keys: [
          %{tag: <<1>>, key: :base64.decode("..."), default: true},
          %{tag: <<2>>, key: :base64.decode("..."), default: false}
        ]

  If you want to store your key in the environment variable, you can use
  `{:system, "VAR"}` syntax:

      config :cloak, Cloak.AES.CTR,
        default: true,
        tag: "AES",
        keys: [
          %{tag: <<1>>, key: {:system, "CLOAK_KEY_PRIMARY"}, default: true},
          %{tag: <<2>>, key: {:system, "CLOAK_KEY_SECONDARY"}, default: false}
        ]

  ### Key Configuration Options

  A key may have the following attributes:

  - `:tag` - The ID of the key. This is included in the ciphertext, and should be
    only a single byte. See `encrypt/2` for more details.

  - `:key` - The AES key to use, in binary. If you store your keys in Base64
    format you will need to decode them first. The key must be 128, 192, or 256 bits
    long (16, 24 or 32 bytes, respectively).

  - `:default` - Boolean. Whether to use this key by default or not.

  ## Upgrading to a New Key

  To upgrade to a new key, simply add the key to the `:keys` array, and set it
  as `default: true`.

      keys: [
        %{tag: <<1>>, key: "old key", default: false},
        %{tag: <<2>>, key: "new key", default: true}
      ]

  After this, your new key will automatically be used for all new encyption, 
  while the old key will be used to decrypt legacy values.

  To migrate everything proactively to the new key, see the `mix cloak.migrate`
  mix task defined in `Mix.Tasks.Cloak.Migrate`.
  """

  @behaviour Cloak.Cipher

  @doc """
  Callback implementation for `Cloak.Cipher.encrypt`. Encrypts a value using
  AES in CTR mode.

  Generates a random IV for every encryption, and prepends the key tag and IV to
  the beginning of the ciphertext. The format can be diagrammed like this:

      +----------------------------------+----------------------+
      |              HEADER              |         BODY         |
      +------------------+---------------+----------------------+
      | Key Tag (1 byte) | IV (16 bytes) | Ciphertext (n bytes) |
      +------------------+---------------+----------------------+

  When this function is called through `Cloak.encrypt/1`, the module's `:tag`
  will be added, and the resulting binary will be in this format:

      +---------------------------------------------------------+----------------------+
      |                         HEADER                          |         BODY         |
      +----------------------+------------------+---------------+----------------------+
      | Module Tag (n bytes) | Key Tag (1 byte) | IV (16 bytes) | Ciphertext (n bytes) |
      +----------------------+------------------+---------------+----------------------+

  The header information allows Cloak to know enough about each ciphertext to
  ensure a successful decryption. See `decrypt/1` for more details.

  **Important**: Because a random IV is used for every encryption, `encrypt/2`
  will not produce the same ciphertext twice for the same value.

  ### Parameters

  - `plaintext` - Any type of value to encrypt.
  - `key_tag` - Optional. The tag of the key to use for encryption.

  ### Example

      iex> encrypt("Hello") != "Hello"
      true

      iex> encrypt("Hello") != encrypt("Hello")
      true
  """
  def encrypt(plaintext, key_tag \\ nil) do
    iv = :crypto.strong_rand_bytes(16)
    key = get_key_config(key_tag) || default_key
    state = :crypto.stream_init(:aes_ctr, get_key_value(key), iv)

    {_state, ciphertext} = :crypto.stream_encrypt(state, to_string(plaintext))
    key.tag <> iv <> ciphertext
  end

  @doc """
  Callback implementation for `Cloak.Cipher.decrypt`. Decrypts a value
  encrypted with AES in CTR mode.

  Uses the key tag to find the correct key for decryption, and the IV included
  in the header to decrypt the body of the ciphertext.

  ### Parameters

  - `ciphertext` - Binary ciphertext generated by `encrypt/2`.

  ### Examples

      iex> encrypt("Hello") |> decrypt
      "Hello"
  """
  def decrypt(<<key_tag::binary-1, iv::binary-16, ciphertext::binary>> = _ciphertext) do
    key = get_key_config(key_tag)
    state = :crypto.stream_init(:aes_ctr, get_key_value(key), iv)

    {_state, plaintext} = :crypto.stream_decrypt(state, ciphertext)
    plaintext
  end

  @doc """
  Callback implementation for `Cloak.Cipher.version`. Returns the tag of the
  current default key.
  """
  def version do
    default_key.tag
  end

  defp get_key_config(tag) do
    Enum.find(config[:keys], fn(key) -> key.tag == tag end)
  end

  defp get_key_value(key_config) do
    case key_config.key do
      {:system, env_var} ->
        System.get_env(env_var)
        |> validate_key(env_var)
        |> decode_key(env_var)

      _ ->
        key_config.key
    end
  end

  defp validate_key(key, env_var) when key in [nil, ""] do
    raise "Expect env variable #{env_var} to define a key, but is empty."
  end
  defp validate_key(key, _), do: key

  defp decode_key(key, env_var) do
    case Base.decode64(key) do
      {:ok, decoded_key} -> decoded_key
      :error -> raise "Expect env variable #{env_var} to be a valid base64 string."
    end
  end

  defp config do
    Application.get_env(:cloak, __MODULE__)
  end

  defp default_key do
    Enum.find config[:keys], fn(key) -> key.default end
  end
end
