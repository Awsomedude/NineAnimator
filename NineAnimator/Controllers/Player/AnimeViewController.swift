//
//  This file is part of the NineAnimator project.
//
//  Copyright © 2018 Marcus Zhou. All rights reserved.
//
//  NineAnimator is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  NineAnimator is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with NineAnimator.  If not, see <http://www.gnu.org/licenses/>.
//

import UIKit
import WebKit
import AVKit
import SafariServices

class AnimeViewController: UITableViewController, ServerPickerSelectionDelegate, AVPlayerViewControllerDelegate {
    //MARK: - Set either one of the following item to initialize the anime view
    var animeLink: AnimeLink?
    
    var episodeLink: EpisodeLink? {
        didSet {
            if let episodeLink = episodeLink {
                self.animeLink = episodeLink.parent
                self.server = episodeLink.server
            }
        }
    }
    
    //MARK: - Managed by AnimeViewController
    @IBOutlet var serverSelectionButton: UIBarButtonItem!
    
    var anime: Anime? {
        didSet {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.informationCell?.animeDescription = self.anime?.description
                
                let sectionsNeededReloading: IndexSet = [1]
                
                if self.anime == nil && oldValue != nil {
                    self.tableView.deleteSections(sectionsNeededReloading, with: .fade)
                }
                
                guard let anime = self.anime else { return }
                
                if self.server == nil {
                    if let recentlyUsedServer = UserDefaults.standard.string(forKey: "server.recent"),
                        anime.servers[recentlyUsedServer] != nil {
                        self.server = recentlyUsedServer
                    } else {
                        self.server = anime.servers.first!.key
                        debugPrint("Info: No server selected. Using \(anime.servers.first!.key)")
                    }
                }
                
                self.serverSelectionButton.title = anime.servers[self.server!]
                self.serverSelectionButton.isEnabled = true
                
                if oldValue == nil {
                    self.tableView.insertSections(sectionsNeededReloading, with: .fade)
                } else {
                    self.tableView.reloadSections(sectionsNeededReloading, with: .fade)
                }
            }
        }
    }
    
    var server: Anime.ServerIdentifier?
    
    // Set episode will update the server identifier as well
    var episode: Episode? {
        didSet {
            guard let episode = episode else { return }
            server = episode.link.server
        }
    }
    
    var informationCell: AnimeDescriptionTableViewCell?
    
    var selectedEpisodeCell: EpisodeTableViewCell?
    
    var episodeRequestTask: NineAnimatorAsyncTask?
    
    var animeRequestTask: NineAnimatorAsyncTask?
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        //Remove lines at the end of the table
        tableView.tableFooterView = UIView()
        
        // If episode is set, use episode's anime link as the anime for display
        if let episode = episode {
            animeLink = episode.parentLink
        }
        
        guard let link = animeLink else { return }
        // Update history
        NineAnimator.default.user.entering(anime: link)
        NineAnimator.default.user.push()
        
        //Update anime title
        title = link.title
        
        // Fetch anime if anime does not exists
        guard anime == nil else { return }
        serverSelectionButton.title = "Select Server"
        serverSelectionButton.isEnabled = false
        animeRequestTask = NineAnimator.default.anime(with: link) {
            [weak self] anime, error in
            guard let anime = anime else {
                debugPrint("Error: \(error!)")
                return
            }
            self?.anime = anime
            // Initiate playback if episodeLink is set
            if self?.episodeLink != nil {
                self?.retriveAndPlay()
            }
        }
    }
    
    override func didMove(toParent parent: UIViewController?) {
        // Cleanup observers and tasks
        episodeRequestTask?.cancel()
        episodeRequestTask = nil
        
        //Sets episode and server to nil
        episode = nil
        
        //Remove all observations
        NotificationCenter.default.removeObserver(self)
    }
}

//MARK: - Table view data source
extension AnimeViewController {
    override func numberOfSections(in tableView: UITableView) -> Int {
        return anime == nil ? 1 : 2
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0:
            return 1
        case 1:
            guard let serverIdentifier = server,
                let episodes = anime?.episodes[serverIdentifier]
                else { return 0 }
            return episodes.count
        default:
            return 0
        }
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch indexPath.section {
        case 0:
            guard let cell = tableView.dequeueReusableCell(withIdentifier: "anime.description") as? AnimeDescriptionTableViewCell
                else { fatalError("cell with wrong type is dequeued") }
            cell.link = animeLink
            cell.animeDescription = anime?.description
            informationCell = cell
            return cell
        case 1:
            guard let cell = tableView.dequeueReusableCell(withIdentifier: "anime.episode") as? EpisodeTableViewCell
                else { fatalError("unable to dequeue reuseable cell") }
            let episodes = anime!.episodes[server!]!
            var episode = episodes[indexPath.item]
            
            if NineAnimator.default.user.episodeListingOrder == .reversed {
                episode = episodes[episodes.count - indexPath.item - 1]
            }
            
            cell.episodeLink = episode
            cell.progressIndicator.episodeLink = episode
            return cell
        default:
            fatalError()
        }
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let cell = tableView.cellForRow(at: indexPath) as? EpisodeTableViewCell else {
            debugPrint("Warning: Cell selection event received when the cell selected is not an EpisodeTableViewCell")
            return
        }
        
        guard cell != selectedEpisodeCell,
            let episodeLink = cell.episodeLink
            else { return }
        
        selectedEpisodeCell = cell
        self.episodeLink = episodeLink
        retriveAndPlay()
    }
    
    func didSelectServer(_ server: Anime.ServerIdentifier) {
        self.server = server
        UserDefaults.standard.set(server, forKey: "server.recent")
        tableView.reloadSections([1], with: .automatic)
        serverSelectionButton.title = anime!.servers[server]
    }
}

//MARK: - Share and select server
extension AnimeViewController {
    @IBAction func onCastButtonTapped(_ sender: Any) {
        RootViewController.shared?.showCastController()
    }
    
    @IBAction func onActionButtonTapped(_ sender: UIBarButtonItem) {
        guard let link = animeLink else { return }
        let activityViewController = UIActivityViewController(activityItems: [link.link], applicationActivities: nil)
        
        if let popover = activityViewController.popoverPresentationController {
            popover.barButtonItem = sender
            popover.permittedArrowDirections = .up
        }
        
        present(activityViewController, animated: true)
    }
    
    @IBAction func onServerButtonTapped(_ sender: Any) {
        let alertView = UIAlertController(title: "Select Server", message: nil, preferredStyle: .actionSheet)
        
        if let popover = alertView.popoverPresentationController {
            popover.barButtonItem = serverSelectionButton
            popover.permittedArrowDirections = .up
        }
        
        for server in anime!.servers {
            let action = UIAlertAction(title: server.value, style: .default) {
                [weak self] _ in
                self?.didSelectServer(server.key)
            }
            if self.server == server.key {
                action.setValue(true, forKey: "checked")
            }
            alertView.addAction(action)
        }
        alertView.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alertView, animated: true)
    }
}

//MARK: - Initiate playback
extension AnimeViewController {
    func retriveAndPlay() {
        guard let episodeLink = episodeLink else { return }
        
        episodeRequestTask?.cancel()
        NotificationCenter.default.removeObserver(self)
        
        func clearSelection() {
            tableView.deselectSelectedRow()
            selectedEpisodeCell = nil
        }
        
        episodeRequestTask = anime!.episode(with: episodeLink) {
            [weak self] episode, error in
            guard let self = self else { return }
            guard let episode = episode else {
                debugPrint("Error: \(error!)")
                return
            }
            self.episode = episode
            
            //Save episode to last playback
            NineAnimator.default.user.entering(episode: episodeLink)
            
            debugPrint("Info: Episode target retrived for '\(episode.name)'")
            debugPrint("- Playback target: \(episode.target)")
            
            if episode.nativePlaybackSupported {
                self.episodeRequestTask = episode.retrive {
                    [weak self] media, error in
                    guard let self = self else { return }
                    self.episodeRequestTask = nil
                    
                    guard let media = media else {
                        debugPrint("Warn: Item not retrived \(error!), fallback to web access")
                        DispatchQueue.main.async { [weak self] in
                            let playbackController = SFSafariViewController(url: episode.target)
                            self?.present(playbackController, animated: true, completion: clearSelection)
                        }
                        return
                    }
                    
                    if CastController.default.isReady {
                        CastController.default.initiate(playbackMedia: media, with: episode)
                        DispatchQueue.main.async {
                            RootViewController.shared?.showCastController()
                            clearSelection()
                        }
                    } else {
                        NativePlayerController.default.play(media: media)
                        clearSelection()
                    }
                }
            } else {
                let playbackController = SFSafariViewController(url: episode.target)
                self.present(playbackController, animated: true, completion: clearSelection)
                self.episodeRequestTask = nil
                episode.update(progress: 1.0)
            }
        }
    }
}