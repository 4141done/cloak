defmodule Cloak do
  @moduledoc """
  This module is Cloak's main entry point. It wraps the encryption and 
  decryption process, ensuring that everything works smoothly without downtime 
  even when there are multiple encryption ciphers and keys in play at the same 
  time.

  ## Configuration

  The actual encryption work is delegated to the cipher module that you specify
  in Cloak's configuration. Cipher modules must adhere to the `Cloak.Cipher`
  behaviour. You can configure a cipher module like so:

      config :cloak, ModuleName,
        default: true,
        tag: "TAG", 
        # any other attributes required by the cipher
        
  ### Options

  Both of these options are required for every cipher:

  - `:default` - Boolean. Determines whether this module will be the default module for
    encryption or decryption.

  - `:tag` - Binary. Used to tag any ciphertext that the cipher module
    generates. This allows Cloak to send a ciphertext to the correct decryption
    cipher when you have multiple ciphers in use at the same time.

  If your cipher module requires additional config options, you can also add 
  those keys to this configuration.

  ## Provided Ciphers

  - `Cloak.AES.CTR` - AES encryption in CTR stream mode.

  If you don't see what you need here, you can implement your own cipher module
  if you adhere to the `Cloak.Cipher` behaviour. (And [open a PR](https://github.com/danielberkompas/cloak), please!)

  ## Ecto Integration

  Once Cloak is configured with a Cipher module, you can use it seamlessly with
  [Ecto](http://hex.pm/ecto) with these `Ecto.Type`s:

  - `Cloak.EncryptedBinaryField`
  - `Cloak.EncryptedFloatField`
  - `Cloak.EncryptedIntegerField`
  - `Cloak.EncryptedMapField`
  - `Cloak.SHA256Field`

  ## Examples

      iex> Cloak.encrypt("Hello") != "Hello"
      true

      iex> Cloak.encrypt("Hello") |> Cloak.decrypt
      "Hello"

      iex> Cloak.version
      <<"AES", 1>>
  """

  {cipher, config} = Cloak.Config.default_cipher
  @cipher cipher
  @tag config[:tag]

  @doc """
  Encrypt a value using the default cipher module. 
  
  The `:tag` of the cipher will be prepended to the output. So, if the cipher 
  was `Cloak.AES.CTR`, and the tag was "AES", the output would be in this 
  format:

      +-------+---------------+
      | "AES" | Cipher output |
      +-------+---------------+

  This tagging allows Cloak to delegate decryption of a ciphertext to the
  correct module when you have multiple ciphers in use at the same time. (For
  example, this can occur while you migrate your encrypted data to a new 
  cipher.)

  ### Parameters

  - `plaintext` - The value to be encrypted.

  ### Example

      Cloak.encrypt("Hello, World!")
      <<"AES", ...>>
  """
  def encrypt(plaintext) do
    @tag <> @cipher.encrypt(plaintext)
  end

  @doc """
  Decrypt a ciphertext with the cipher module it was encrypted with.

  `encrypt/1` includes the `:tag` of the cipher module that generated the
  encryption in the ciphertext it outputs. `decrypt/1` can then use this tag to
  find the right module on decryption.

  ### Parameters

  - `ciphertext` - A binary of ciphertext generated by `encrypt/1`.

  ### Example

  If the cipher module responsible had the tag "AES", Cloak will find the module
  using that tag, strip it off, and hand the remaining ciphertext to the module
  for decryption.

      iex> ciphertext = Cloak.encrypt("Hello world!")
      ...> <<"AES", _ :: bitstring>> = ciphertext
      ...> Cloak.decrypt(ciphertext)
      "Hello world!"
  """
  for {cipher, config} <- Cloak.Config.all do
    def decrypt(unquote(config[:tag]) <> ciphertext) do
      unquote(cipher).decrypt(ciphertext)
    end
  end
  def decrypt(invalid) do
    raise ArgumentError, "No cipher found to decrypt #{inspect invalid}."
  end

  @doc """
  Returns the default cipher module's tag combined with the result of that
  cipher's `version/0` function.

  It is used by `Cloak.Model` to record which cipher was used to encrypt a row
  in a database table. This is very useful when migrating to a new cipher or new
  encryption key, because you'd be able to query your database to find records
  that need to be migrated.
  """
  def version do
    @tag <> @cipher.version
  end
end
