/// Name(s): Anthony Valles, Garrett Jones
/// Professor: Dr. Cheon
/// Assignment 2 - Dart Omok Project
/// Due Date: 04/12/2022
/// CS 3360 (CRN - 29507)

import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

void main(List<String> arguments) async {
  var controller = new Controller();
  controller.start();
}

class Controller {
  start() async {
    /// Variable that determines if cheat mode is activated
    var cheatMode = false;

    var ui = ConsoleUI();
    ui.showMessage('Welcome to omok game!');

    // Get server URL
    var url = ui.promptServer();

    while(true) {
      ui.showMessage("Obtaining server information...");
      /// check if url is valid
      try {
        var tryUrl = Uri.parse(url + 'info');
        var response = await http.get(tryUrl);
        var statusCode = response.statusCode;
        if (statusCode < 200 || statusCode > 400) {
          ui.showMessage('Server connection failed ($statusCode).');
        } else {
          ui.showMessage('Connection established');
          break;
        }
      }

      on FormatException {
        print("Error - url not formatted correctly");
      }
      on ArgumentError {
        print("Error - url not formatted correctly");
      }
      on SocketException{
        print("Error - could not connect to host");
      }
      /*on NoSuchMethodError{
        print("Error - No body in URL response");
      }*/
      url = ui.promptServer();  //prompt again if invalid
    }


    // Pass url to model
    var net = WebClient(url);
    var info = await net.getInfo();
    var strategy = ui.promptStrategy(['R', 'S']);
    ui.showMessage("Creating new game with $strategy...");

    /// Get new pid of game
    var newGame = await net.createNewGame(strategy);
    var newResponse = json.decode(newGame.body);  /// contains pid

    /// Check for any error codes
    var statusCode = newGame.statusCode;
    if (statusCode < 200 || statusCode > 400) {
      ui.showMessage('Server connection failed ($statusCode).');
    } else {
      ui.showMessage('Response body: ${newResponse}');
    }

    /// Create board
    var size = info['size'];
    var boardSize = size * size;
    ui.board = List.filled(boardSize, ' *', growable: false);
    ui.showBoard(info['size']);

    /// Get player move and make request to server
    var move = ui.promptMove();

    while (move != -1) {

      try {
        /// Subtract 1 from each coordinate of move to align with ui
        List<String>? move_list = new List<String>.filled(2, "", growable: true);
        move_list = move?.split(",");
        List<int>? int_list = new List<int>.filled(2, 0, growable: true);
        if (move_list != null && move_list.length == 2) {
          int_list[0] = int.tryParse(move_list[0])! - 1;
          int_list[1] = int.tryParse(move_list[1])! - 1;
        }

        else {
          throw FormatException();
        }

        move = int_list[0].toString() + "," + int_list[1].toString();
      } on RangeError {
        ui.showMessage("Range Error");
      }catch (e){
      }

      /// Get response from play

      var response = await net.makePlay(newResponse['pid'], move);
      var playResponse = json.decode(response.body);


      /// Check for connection error
      var statusCode = response.statusCode;
      if (statusCode < 200 || statusCode > 400) {
        ui.showMessage('Server connection failed ($statusCode).');
      }

      /// Update board and check if response is false
      /// If response is true, proceed with rest of code
      if (playResponse['response'] != false) {
        /// Place player & computer moves on board
        var p1x = playResponse['ack_move']['x'];
        var p1y = playResponse['ack_move']['y'];

        /// Place computer move on board
        if (playResponse['ack_move']['isWin'] != true) {
          var p2x = playResponse['move']['x'];
          var p2y = playResponse['move']['y'];
          var p2Move = (p2y * size) + (p2x);
          ui.board[p2Move] = ' X';
        }

        /// Place player move on board
        var p1Move = (p1y * size) + (p1x);
        ui.board[p1Move] = ' O';

        /// Check for player win
        if (playResponse['ack_move']['isWin'] == true) {
          ui.showMessage("Player wins!");
          ui.showMessage("Winning Row: ");
          ui.showMessage(playResponse['ack_move']['row'].toString());

          /// For each element in winning row, set board[elem] = ' W'
          var count = 0;
          var x, y;
          for (final e in playResponse['ack_move']['row']) {
            if ((count % 2) == 0) { x = e; }
            if ((count % 2 == 1)) { y = e; }
            if (x != null && y != null && ((count % 2) == 1)) {
              var move = (y * size) + x;
              ui.board[move] = ' W';
            }
            count++;
          }
          ui.showBoard(info['size']);
          break;
        }

        /// Check for computer win
        if (playResponse['move']['isWin'] == true) {
          ui.showMessage("Computer wins!");
          ui.showMessage("Winning Row: ");
          ui.showMessage(playResponse['move']['row'].toString());

          /// For each element in winning row, set board[elem] = ' W'
          var count = 0;
          var x, y;
          for (final e in playResponse['move']['row']) {
            if ((count % 2) == 0) { x = e; }
            if ((count % 2 == 1)) { y = e; }
            if (x != null && y != null && ((count % 2) == 1)) {
              var move = (y * size) + x;
              ui.board[move] = ' W';
            }
            count++;
          }
          ui.showBoard(info['size']);
          break;
        }
        /// Check for draw
        if (playResponse['ack_move']['isDraw'] == true ||
            playResponse['move']['isDraw'] == true) {
          ui.showMessage("Draw!");
          ui.showBoard(info['size']);
          break;
        }
      } else if (move == 'cheat mode') {
        if (cheatMode) {
          cheatMode = false;
          print("Cheat Mode Deactivated");
        } else {
          cheatMode = true;
          print("Cheat Mode Activated");
        }
      } else {
        ui.showMessage(playResponse['reason'] + ' Try Again: ');
      }

      if (cheatMode) {
        nextMove(ui.board, info['size'], boardSize);
      }
      /// Show current board and get next player move
      if (playResponse['response'] != false) {
        ui.showBoard(info['size']);
      }
      move = ui.promptMove();
    }
  }
  void nextMove(var board, var size, var boardSize) {
    var noteworthyStrip = List.filled(5, ' _', growable: false);
    int maxP1Strip = 0;
    int maxP2Strip = 0;
    num p1x = -1, p1y = -1, bestOption = -1;

    /// Check each space on the board
    for (int i = 0; i < boardSize; i++) {
      if (board[i] == ' O' || board[i] == ' X') {
        var bound1 = i % size;
        var bound2 = i - bound1;

        /// Check if strip exceeds board
        for (int m = -4, n = m+2; m <= 4; m++, n++) {
          var a = ((m.abs() % 4) * m).sign;
          var b = ((n.abs() % 4) * n).sign;
          var checkPieces = true;
          checkPieces = a < 0 && (bound1 - 4 < 0) ? false : checkPieces;
          checkPieces = a > 0 && (bound1 + 4 >= size) ? false : checkPieces;
          checkPieces = b < 0 && (bound2 - (4 * size) < 0) ? false : checkPieces;
          checkPieces = b > 0 && (bound2 + (4 * size) >= boardSize) ? false : checkPieces;

          /// Check pieces if strip does not exceed board
          if (checkPieces) {
            var pieces = List.filled(5, ' *', growable: false);
            num x = a;
            var y = b * size;
            pieces[0] = board[i+(x * 0)+(y * 0)];
            pieces[1] = board[i+(x * 1)+(y * 1)];
            pieces[2] = board[i+(x * 2)+(y * 2)];
            pieces[3] = board[i+(x * 3)+(y * 3)];
            pieces[4] = board[i+(x * 4)+(y * 4)];

            /// count elements & return list
            var elements = countElements(pieces);

            /// check list purity (make sure strip doesn't have a mix
            /// of ' X' and ' O's
            if (elements[0] == 0 || elements[1] == 0) {
              /// Found p1 (player) largest strip
              if (elements[0] > maxP1Strip) {
                maxP1Strip = elements[0];
                if (maxP1Strip > maxP2Strip) {
                  noteworthyStrip = pieces;
                  bestOption = i + (elements[2] * x) + (elements[2] * y);
                }
              }

              /// Found p2 (computer) largest strip
              if (elements[1] > maxP2Strip) {
                maxP2Strip = elements[1];
                if (maxP2Strip >= maxP1Strip) {
                  noteworthyStrip = pieces;
                  bestOption = i + (elements[2] * x) + (elements[2] * y);
                }
              }
            }
          } /// end of "checkPieces" block
        } /// end of 2nd for loop
      } /// end of if block
    } /// end of 1st for loop

    /// Print out best player option
    p1x = (bestOption % size)+1;
    p1y = (bestOption ~/ size)+1;
    print("(Cheat Mode) - Best Option: "+p1x.toString()+", "+p1y.toString());
    print("Winning/Losing Sequence:"+noteworthyStrip.toString());
  }

  List countElements(var pieces) {
    /// checks if list is pure (meaning no mix between ' O' and ' X')
    var elements = List.filled(3, 0, growable: false);
    elements[2] = -1;
    for (int i = 0; i < 5; i++) {
      if (pieces[i] == ' O') { elements[0]++; }
      else if (pieces[i] == ' X') { elements[1]++; }
      else { elements[2] = elements[2] == -1 ? i : elements[2]; }
    }
    /// return list
    return elements;
  }
}
/// ---- Model Classes ---- ///

/// Board class
class Board {
  var size;
  var boardSize;

  Board(size){
    this.size = size;
    this.boardSize = size * size;
  }
}

var defaultURL = "https://www.cs.utep.edu/cheon/cs3360/project/omok/";

/// Web Client
class WebClient {
  var serverUrl;
  WebClient(this.serverUrl);

  /// get game info from server and return
  getInfo() async{
    var url = Uri.parse(this.serverUrl + 'info');
    var response = await http.get(url);
    var info = json.decode(response.body);
    return info;
  }
  /// get new game info including pid
  createNewGame(strategy) async {
    var url = Uri.parse(this.serverUrl +'new/?strategy=$strategy');
    var response = await http.get(url);
    return response;
  }
  ///get play info and return
  makePlay(pid, move) async {
    var url = Uri.parse(this.serverUrl +'play/?pid=$pid&move=$move');
    var response = await http.get(url);
    return response;
  }
}

/// --- View Classes --- ///

class ConsoleUI {
  var board;
  void showMessage(String msg) {
    print(msg);
  }

  promptServer() {
    print('Enter server URL or enter 1 for default (default value is $defaultURL): ');
    ///check whether string is in json form
    ///read user response using while loop and return

    String? input = stdin.readLineSync();
    if (input == "1"){
      return defaultURL;
    }
    return input;
  }

  String? promptStrategy(List<String> strategies){
    print('Choose your strategy');
    print('Select the server strategy: Press Enter for Smart or enter "1" for Random');
    String? input = stdin.readLineSync();
    if (input == "1"){
      return 'Random';
    }
    return 'Smart';
  }

  void showBoard(boardSize) {
    print('Current board....');
    stdout.write('  x 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5\n');
    stdout.write('y ------------------------------');

    var count = 1;
    for (int i = 0; i < (boardSize*boardSize); i++) {
      if (i % (boardSize) == 0) {
        stdout.write('\n$count| ');
        count++;
        if (count >= 10){
          count = 0;
        }
      }
      stdout.write(board[i]);

    }
    stdout.write('\n');
  }

  String? promptMove() {
    print('Enter an xy coordinate pair (e.g. 10, 12): ');
    var move = stdin.readLineSync();
    return move;
  }
}